// ============================================================================
//  liquidityLogic.ts — Off-chain CRE simulation for Uniswap V2 LP operations
//
//  Operations covered:
//    ADD         addLiquidity(tokenA, tokenB, amtADesired, amtBDesired, minA, minB, to, dl)
//    ADD_ETH     addLiquidityETH(token, amtTokenDesired, minToken, minETH, to, dl)
//    REMOVE      removeLiquidity(tokenA, tokenB, liquidity, minA, minB, to, dl)
//    REMOVE_ETH  removeLiquidityETH(token, liquidity, minToken, minETH, to, dl)
//
//  Unique vulnerabilities to be detected 
//
//  1. TRACE-BASED
//     DELEGATECALL to unknown — router/pair calling external contract mid-operationType
//     SELFDESTRUCT during execution
//     CREATE/CREATE2 during execution (malicious factory deployment)
//     Approval drain — LP or token approved to unknown spender
//     Reentrancy in UniV2 pair (only present if _unlocked guard is missing)
//     Owner/fee-receiver sweep — token transfer to factory owner during mint
//
//  2. ECONOMIC
//     First-depositor attack — totalSupply == 0 means ratio is set adversarially
//     Pool ratio vs Chainlink fair ratio — detects pre-manipulation (sandwich)
//     Actual LP minted vs expected LP — formula verification
//     Excess token loss — value donated due to ratio mismatch between desired
//       amounts and current pool ratio
//     LP honeypot — add immediately then simulate remove; if remove reverts,
//       the LP token is a honeypot (you can add but cannot take out)
//     Oracle staleness on both tokens
// ============================================================================

import { ethers } from "ethers";
import {
    LiquidityOpType, LiquidityOffChainResult,
    LiquidityTraceFindings, LiquidityEconomicFindings,
    RiskLevel, RISK_WEIGHTS, THRESHOLDS,
} from "./common/types.js";
import { getTokenPrice } from "./common/chainlink.js";
import {
    findDangerousDelegateCall, findSelfDestruct, findUnexpectedCreates,
    findReentrancy, findApprovalDrain, findOwnerSweep, decodeRevertReason,
} from "./common/traceAnalysis.js";
import {
    buildERC20Override, buildERC20BalanceOverride, buildNativeETHOverride,
} from "./common/tokenOverrides.js";
import { checkContractVerified } from "./common/arbiscan.js";

// ─── Uniswap V2 interfaces ────────────────────────────────────────────────────

const ROUTER_IFACE = new ethers.utils.Interface([
    "function addLiquidity(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity)",
    "function addLiquidityETH(address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)",
    "function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline) returns (uint256 amountA, uint256 amountB)",
    "function removeLiquidityETH(address token, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) returns (uint256 amountToken, uint256 amountETH)",
    "function factory() view returns (address)",
]);

const FACTORY_IFACE = new ethers.utils.Interface([
    "function getPair(address tokenA, address tokenB) view returns (address pair)",
]);

const PAIR_IFACE = new ethers.utils.Interface([
    "function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
    "function totalSupply() view returns (uint256)",
    "function token0() view returns (address)",
    "function token1() view returns (address)",
    "function kLast() view returns (uint256)",
]);

const WETH = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";

// ─── Context shape ────────────────────────────────────────────────────────────

interface LiquidityContext {
    opType:        LiquidityOpType;
    from:          string;
    routerAddress: string;
    data:          string;    // ABI-encoded calldata from extension

    // ADD / ADD_ETH
    tokenA?:          string;   // omitted for ADD_ETH (use `token`)
    tokenB?:          string;
    token?:           string;   // ADD_ETH only
    amountADesired?:  string;
    amountBDesired?:  string;
    amountTokenDesired?: string;
    amountETHDesired?:   string;  // = msg.value for ADD_ETH
    amountAMin?:      string;
    amountBMin?:      string;
    amountTokenMin?:  string;
    amountETHMin?:    string;

    // REMOVE / REMOVE_ETH
    lpAmount?:        string;   // LP tokens to burn
    to?:              string;   // address to send received tokens
}

// ─── Main entry point ─────────────────────────────────────────────────────────

export const liquidityLogic = async (runtime: any, context: any): Promise<LiquidityOffChainResult> => {
    const liquidityContext = context.data as LiquidityContext;
    const { opType, from, routerAddress, data } = liquidityContext;
    const operationType   = opType as LiquidityOpType;
    const evm  = runtime.capabilities.evm("arbitrum-mainnet");
    const http = runtime.capabilities.http;
    const reciever = liquidityContext.to ?? from;

    // ─── 1. Resolve tokenA / tokenB from context ──────────────────────────────
    // ADD_ETH: tokenA = token param, tokenB = WETH
    // REMOVE_ETH: same mapping
    const rawTokenA = liquidityContext.tokenA ?? liquidityContext.token ?? "";
    const rawTokenB = liquidityContext.tokenB ?? (_isETHoperation(operationType) ? WETH : "");

    if (!rawTokenA || !rawTokenB) throw new Error("CRE_LP: tokenA and tokenB must be provided");

    const [decimalsA, decimalsB] = await Promise.all([
        evm.read({ to: rawTokenA, func: "decimals()" }).then(Number),
        _isETHoperation(operationType) ? Promise.resolve(18) : evm.read({ to: rawTokenB, func: "decimals()" }).then(Number),
    ]);

    // ─── 2. Discover pair address and pool state ───────────────────────────────
    const factoryAddr: string = await evm.read({ to: routerAddress, func: "factory()" });

    const pairAddress: string = await evm.read({
        to:   factoryAddr,
        func: "getPair(address,address)",
        args: [rawTokenA, rawTokenB],
    });

    const isPairZero = pairAddress === ethers.constants.AddressZero;

    let reserveA     = ethers.BigNumber.from(0);
    let reserveB     = ethers.BigNumber.from(0);
    let lpTotalSupply = ethers.BigNumber.from(0);
    let pairToken0   = "";
    let factoryOwner = ethers.constants.AddressZero;

    if (!isPairZero) {
        const [reserves, supply, token0] = await Promise.all([
            evm.read({ to: pairAddress, func: "getReserves()" }),
            evm.read({ to: pairAddress, func: "totalSupply()"  }),
            evm.read({ to: pairAddress, func: "token0()"       }),
        ]);

        pairToken0   = token0.toLowerCase();
        lpTotalSupply = ethers.BigNumber.from(supply);

        // Align reserves to tokenA/tokenB order
        const [r0, r1] = [ethers.BigNumber.from(reserves[0]), ethers.BigNumber.from(reserves[1])];
        if (pairToken0 === rawTokenA.toLowerCase()) {
            reserveA = r0; reserveB = r1;
        } else {
            reserveA = r1; reserveB = r0;
        }

        // Get factory owner (for sweep detection)
        try {
            factoryOwner = await evm.read({ to: factoryAddr, func: "owner()" });
        } catch { /* some factories use feeToSetter */ }
        if (factoryOwner === ethers.constants.AddressZero) {
            try {
                factoryOwner = await evm.read({ to: factoryAddr, func: "feeToSetter()" });
            } catch { /* leave as zero */ }
        }
    }

    const isFirstDeposit = lpTotalSupply.isZero();

    // ─── 3. Pool ratio vs Chainlink fair ratio ────────────────────────────────
    const [oracleA, oracleB] = await Promise.all([
        getTokenPrice(evm, rawTokenA),
        getTokenPrice(evm, rawTokenB),
    ]);

    // poolRatio: reserveB per reserveA (1e18 scaled), adjusted for decimals
    let poolRatio  = ethers.BigNumber.from(0);
    let oracleRatio = ethers.BigNumber.from(0);
    let ratioDeviationBps = 0;

    if (!reserveA.isZero() && !reserveB.isZero()) {
        // Normalize to 1e18 for consistent ratio
        const normalizedReserveA = reserveA.mul(ethers.BigNumber.from(10).pow(18 - decimalsA));
        const normalizedReserveB = reserveB.mul(ethers.BigNumber.from(10).pow(18 - decimalsB));
        poolRatio   = normalizedReserveB.mul(ethers.utils.parseUnits("1", 18)).div(normalizedReserveA);
    }

    if (oracleA.found && oracleB.found && !oracleB.priceUSD.isZero()) {
        // oracleRatio: how much tokenB you should get per tokenA (fair market)
        oracleRatio = oracleA.priceUSD.mul(ethers.utils.parseUnits("1", 18)).div(oracleB.priceUSD);
    }

    if (!poolRatio.isZero() && !oracleRatio.isZero()) {
        const difference  = poolRatio.gt(oracleRatio)
            ? poolRatio.sub(oracleRatio)
            : oracleRatio.sub(poolRatio);
        ratioDeviationBps = difference.mul(10000).div(oracleRatio).toNumber();
    }

    // ─── 4. Build state overrides ─────────────────────────────────────────────
    const stateOverrides = _buildLPOverrides(operationType, {
        from, routerAddress, pairAddress: isPairZero ? "" : pairAddress,
        rawTokenA, rawTokenB, decimalsA, decimalsB, liquidityContext,
    });

    // ─── 5. Run primary simulation ────────────────────────────────────────────
    let simulation: any;
    try {
        simulation = await evm.call({
            from,
            to:    routerAddress,
            data,
            value: _isETHoperation(operationType) && _isAdd(operationType) ? (liquidityContext.amountETHDesired ?? "0x0") : "0x0",
            trace: true,
            stateOverrides,
        });
    } catch (err: any) {
        return _errorResult(operationType, `SIMULATION_EXCEPTION:${err?.message ?? "unknown"}`);
    }

    const simulationReverted  = simulation.status === "0x0";
    const revertReason = simulationReverted ? decodeRevertReason(simulation.data ?? "0x") : "";

    // ─── 6. Decode output ─────────────────────────────────────────────────────
    let actualAmountA  = ethers.BigNumber.from(0);
    let actualAmountB  = ethers.BigNumber.from(0);
    let actualLPMinted = ethers.BigNumber.from(0);
    let actualReceivedA = ethers.BigNumber.from(0);
    let actualReceivedB = ethers.BigNumber.from(0);

    if (!simulationReverted && simulation.data && simulation.data !== "0x") {
        try {
            if (_isAdd(operationType)) {
                // addLiquidity returns (uint256 amountA, uint256 amountB, uint256 liquidity)
                const [a, b, lp] = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "uint256", "uint256"], simulation.data
                );
                actualAmountA  = a as ethers.BigNumber;
                actualAmountB  = b as ethers.BigNumber;
                actualLPMinted = lp as ethers.BigNumber;
            } else {
                // removeLiquidity returns (uint256 amountA, uint256 amountB)
                const [a, b] = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "uint256"], simulation.data
                );
                actualReceivedA = a as ethers.BigNumber;
                actualReceivedB = b as ethers.BigNumber;
            }
        } catch { /* leave at zero */ }
    }

    // ─── 7. Expected LP minted (formula) ─────────────────────────────────────
    // V2 formula: LP = min(amountA * totalSupply / reserveA, amountB * totalSupply / reserveB)
    // For first deposit: LP = sqrt(amountA * amountB) - MINIMUM_LIQUIDITY
    let expectedLPMinted    = ethers.BigNumber.from(0);
    let lpMintDiscrepancyBps = 0;
    let excessTokenALost    = ethers.BigNumber.from(0);
    let excessTokenBLost    = ethers.BigNumber.from(0);
    let excessValueLostUSD  = ethers.BigNumber.from(0);

    if (_isAdd(operationType) && !simulationReverted) {
        if (!lpTotalSupply.isZero() && !reserveA.isZero() && !reserveB.isZero()) {
            const lpFromA = actualAmountA.mul(lpTotalSupply).div(reserveA);
            const lpFromB = actualAmountB.mul(lpTotalSupply).div(reserveB);
            expectedLPMinted = lpFromA.lt(lpFromB) ? lpFromA : lpFromB;

            if (!expectedLPMinted.isZero() && actualLPMinted.lt(expectedLPMinted)) {
                const difference = expectedLPMinted.sub(actualLPMinted);
                lpMintDiscrepancyBps = difference.mul(10000).div(expectedLPMinted).toNumber();
            }

            // Excess tokens: difference between desired and actual added
            const desiredA = ethers.BigNumber.from(liquidityContext.amountADesired ?? liquidityContext.amountTokenDesired ?? "0");
            const desiredB = ethers.BigNumber.from(liquidityContext.amountBDesired ?? liquidityContext.amountETHDesired ?? "0");

            if (desiredA.gt(actualAmountA)) excessTokenALost = desiredA.sub(actualAmountA);
            if (desiredB.gt(actualAmountB)) excessTokenBLost = desiredB.sub(actualAmountB);

            // USD value lost if oracles available
            if (oracleA.found && !excessTokenALost.isZero()) {
                const lostA36 = excessTokenALost
                    .mul(ethers.BigNumber.from(10).pow(36 - decimalsA))
                    .mul(oracleA.priceUSD)
                    .div(ethers.BigNumber.from(10).pow(18));
                excessValueLostUSD = excessValueLostUSD.add(lostA36);
            }
            if (oracleB.found && !excessTokenBLost.isZero()) {
                const lostB36 = excessTokenBLost
                    .mul(ethers.BigNumber.from(10).pow(36 - decimalsB))
                    .mul(oracleB.priceUSD)
                    .div(ethers.BigNumber.from(10).pow(18));
                excessValueLostUSD = excessValueLostUSD.add(lostB36);
            }
        }
    }

    // ─── 8. LP honeypot check — add → remove simulation ───────────────────────
    // Only run for add operations. We attempt to remove the LP shares we just minted.
    // If removal reverts, the LP is a honeypot — you can add but never remove.
    let isRemovalFrozen    = false;
    let removalRevertReason = "";
    let removalSimAmountA  = ethers.BigNumber.from(0);
    let removalSimAmountB  = ethers.BigNumber.from(0);

    if (_isAdd(operationType) && !simulationReverted && actualLPMinted.gt(0) && !isPairZero) {
        try {
            const removeData = _isETHoperation(operationType)
                ? ROUTER_IFACE.encodeFunctionData("removeLiquidityETH", [
                    rawTokenA, actualLPMinted, 0, 0, reciever,
                    Math.floor(Date.now() / 1000) + 3600,
                  ])
                : ROUTER_IFACE.encodeFunctionData("removeLiquidity", [
                    rawTokenA, rawTokenB, actualLPMinted, 0, 0, reciever,
                    Math.floor(Date.now() / 1000) + 3600,
                  ]);

            // Give `from` the LP tokens to burn
            const lpOverride = buildERC20Override({
                tokenAddress: pairAddress,
                user:         from,
                amount:       actualLPMinted.mul(2),
                spender:      routerAddress,
            });

            const removeSim = await evm.call({
                from,
                to:    routerAddress,
                data:  removeData,
                trace: false,
                stateOverrides: {
                    [pairAddress]: lpOverride,
                    // Give the pair reserves so it can pay out
                    [rawTokenA]:   buildERC20BalanceOverride(rawTokenA, pairAddress, reserveA.mul(10)),
                    [rawTokenB]:   _isETHoperation(operationType)
                        ? buildNativeETHOverride(ethers.utils.parseEther("1000"))
                        : buildERC20BalanceOverride(rawTokenB, pairAddress, reserveB.mul(10)),
                },
            });

            if (removeSim.status === "0x0") {
                isRemovalFrozen     = true;
                removalRevertReason = decodeRevertReason(removeSim.data ?? "0x");
            } else if (removeSim.data && removeSim.data !== "0x") {
                const [a, b] = ethers.utils.defaultAbiCoder.decode(
                    ["uint256", "uint256"], removeSim.data
                );
                removalSimAmountA = a as ethers.BigNumber;
                removalSimAmountB = b as ethers.BigNumber;
            }
        } catch (err: any) {
            isRemovalFrozen     = true;
            removalRevertReason = `REMOVE_SIM_EXCEPTION:${err?.message ?? "unknown"}`;
        }
    }

    // ─── 9. Trace analysis ────────────────────────────────────────────────────
    const trace = simulation.trace ?? [];

    // Safe delegatecall targets: the router and known UniV2 pair address
    const safeTargets = [routerAddress, ...(isPairZero ? [] : [pairAddress])];
    const delegateResult  = findDangerousDelegateCall(trace, safeTargets);
    const hasSelfDestruct = findSelfDestruct(trace);
    const creates         = findUnexpectedCreates(trace);
    const reentrant       = findReentrancy(trace);

    // Legitimate approve targets: router, pair, the two tokens, user
    const legitApprove = [routerAddress, pairAddress, rawTokenA, rawTokenB, from, reciever];
    const approvalResult = findApprovalDrain(trace, legitApprove);

    // Sweep: factory owner taking tokens during mint/burn
    const sweepResult = findOwnerSweep(trace, factoryOwner);

    const traceFindings: LiquidityTraceFindings = {
        hasDangerousDelegateCall: delegateResult.found,
        delegateCallTarget:       delegateResult.target,
        hasSelfDestruct,
        hasUnexpectedCreate:      creates.length > 0,
        createAddresses:          creates,
        hasApprovalDrain:         approvalResult.found,
        approvalDrainSpender:     approvalResult.spender,
        hasReentrancy:            reentrant.found,
        reentrancyAddress:        reentrant.address,
        hasOwnerSweep:            sweepResult.found,
        sweepAmount:              sweepResult.amount,
        sweepToken:               sweepResult.token,
    };

    // ─── 10. Contract verification ────────────────────────────────────────────
    const [routerVerif, pairVerif, tokenAVerif, tokenBVerif] = await Promise.all([
        checkContractVerified(http, routerAddress),
        isPairZero ? Promise.resolve({ isVerified: false }) : checkContractVerified(http, pairAddress),
        checkContractVerified(http, rawTokenA),
        _isETHoperation(operationType) ? Promise.resolve({ isVerified: true }) : checkContractVerified(http, rawTokenB),
    ]);

    // ─── 11. Assemble economic findings ──────────────────────────────────────

    const economicFindings: LiquidityEconomicFindings = {
        simulationReverted: simulationReverted,
        revertReason,
        actualAmountA:        actualAmountA.toString(),
        actualAmountB:        actualAmountB.toString(),
        actualLPMinted:       actualLPMinted.toString(),
        expectedLPMinted:     expectedLPMinted.toString(),
        lpMintDiscrepancyBps,
        excessTokenALost:     excessTokenALost.toString(),
        excessTokenBLost:     excessTokenBLost.toString(),
        excessValueLostUSD:   excessValueLostUSD.toString(),
        actualReceivedA:      actualReceivedA.toString(),
        actualReceivedB:      actualReceivedB.toString(),
        pairAddress:          isPairZero ? "" : pairAddress,
        lpTotalSupply:        lpTotalSupply.toString(),
        reserveA:             reserveA.toString(),
        reserveB:             reserveB.toString(),
        isFirstDeposit,
        poolRatio:            poolRatio.toString(),
        oracleRatio:          oracleRatio.toString(),
        ratioDeviationBps,
        isRemovalFrozen,
        removalRevertReason,
        removalSimAmountA:    removalSimAmountA.toString(),
        removalSimAmountB:    removalSimAmountB.toString(),
        tokenAPriceUSD:       oracleA.priceUSD.toString(),
        tokenBPriceUSD:       oracleB.priceUSD.toString(),
        tokenAOracleStale:    oracleA.isStale,
        tokenBOracleStale:    oracleB.isStale,
        tokenAOracleAge:      oracleA.ageSeconds,
        tokenBOracleAge:      oracleB.ageSeconds,
    };

    const { riskScore, riskLevel } = _computeLPRisk(traceFindings, economicFindings);

    const isSafe =
        riskLevel === "SAFE"                       &&
        !simulationReverted                        &&
        !traceFindings.hasDangerousDelegateCall    &&
        !traceFindings.hasSelfDestruct             &&
        !traceFindings.hasOwnerSweep               &&
        !traceFindings.hasApprovalDrain            &&
        !economicFindings.isRemovalFrozen          &&
        !economicFindings.isFirstDeposit;

    return {
        isSafe, riskLevel, riskScore, operation: operationType,
        trace: traceFindings, economic: economicFindings,
        routerVerified: routerVerif.isVerified,
        pairVerified:   pairVerif.isVerified,
        tokenAVerified: tokenAVerif.isVerified,
        tokenBVerified: tokenBVerif.isVerified,
        simulatedAt: Math.floor(Date.now() / 1000),
        network: "arbitrum-mainnet",
    };
};

// ─── State override builder ───────────────────────────────────────────────────

function _buildLPOverrides(
    operationType: LiquidityOpType,
    params: {
        from:         string;
        routerAddress: string;
        pairAddress:  string;
        rawTokenA:    string;
        rawTokenB:    string;
        decimalsA:    number;
        decimalsB:    number;
        liquidityContext:          LiquidityContext;
    }
): Record<string, any> {
    const overrides: Record<string, any> = {};

    if (_isAdd(operationType)) {
        // Give user tokenA (ERC20) + allowance to router
        const amtA = ethers.BigNumber.from(params.liquidityContext.amountADesired ?? params.liquidityContext.amountTokenDesired ?? "0");
        if (amtA.gt(0)) {
            overrides[params.rawTokenA] = buildERC20Override({
                tokenAddress: params.rawTokenA,
                user:         params.from,
                amount:       amtA.mul(2),
                spender:      params.routerAddress,
            });
        }

        if (_isETHoperation(operationType)) {
            // ETH override: set native balance of user
            const ethAmt = ethers.BigNumber.from(params.liquidityContext.amountETHDesired ?? "0");
            overrides[params.from] = buildNativeETHOverride(ethAmt.mul(2));
        } else {
            // Give user tokenB (ERC20) + allowance to router
            const amtB = ethers.BigNumber.from(params.liquidityContext.amountBDesired ?? "0");
            if (amtB.gt(0)) {
                overrides[params.rawTokenB] = buildERC20Override({
                    tokenAddress: params.rawTokenB,
                    user:         params.from,
                    amount:       amtB.mul(2),
                    spender:      params.routerAddress,
                });
            }
        }
    } else {
        // REMOVE: give user the LP tokens + allowance to router
        const lpAmt = ethers.BigNumber.from(params.liquidityContext.lpAmount ?? "0");
        if (lpAmt.gt(0) && params.pairAddress) {
            overrides[params.pairAddress] = buildERC20Override({
                tokenAddress: params.pairAddress,
                user:         params.from,
                amount:       lpAmt.mul(2),
                spender:      params.routerAddress,
            });
        }
        // Also give pair enough reserves to pay out
        overrides[params.rawTokenA] = buildERC20BalanceOverride(
            params.rawTokenA, params.pairAddress,
            ethers.utils.parseUnits("1000000", params.decimalsA)
        );
        if (!_isETHoperation(operationType)) {
            overrides[params.rawTokenB] = buildERC20BalanceOverride(
                params.rawTokenB, params.pairAddress,
                ethers.utils.parseUnits("1000000", params.decimalsB)
            );
        }
    }

    return overrides;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function _isETHoperation(operationType: LiquidityOpType): boolean {
    return operationType === "ADD_ETH" || operationType === "REMOVE_ETH";
}

function _isAdd(operationType: LiquidityOpType): boolean {
    return operationType === "ADD" || operationType === "ADD_ETH";
}

// ─── Risk scoring ─────────────────────────────────────────────────────────────

function _computeLPRisk(
    t: LiquidityTraceFindings,
    e: LiquidityEconomicFindings
): { riskScore: number; riskLevel: RiskLevel } {
    let s = 0;
    const m = (w: number) => { s = Math.max(s, w); };

    if (t.hasDangerousDelegateCall) m(RISK_WEIGHTS.DANGEROUS_DELEGATECALL);
    if (t.hasSelfDestruct)          m(RISK_WEIGHTS.SELFDESTRUCT);
    if (t.hasOwnerSweep)            m(RISK_WEIGHTS.OWNER_SWEEP);
    if (t.hasApprovalDrain)         m(RISK_WEIGHTS.APPROVAL_DRAIN);
    if (e.isRemovalFrozen)          m(RISK_WEIGHTS.LP_REMOVAL_FROZEN);
    if (e.simulationReverted)       m(RISK_WEIGHTS.SIMULATION_REVERT);
    if (e.isFirstDeposit)           m(RISK_WEIGHTS.FIRST_DEPOSIT);
    if (t.hasUnexpectedCreate)      m(RISK_WEIGHTS.UNEXPECTED_CREATE);
    if (t.hasReentrancy)            m(RISK_WEIGHTS.REENTRANCY);
    if (e.tokenAOracleStale || e.tokenBOracleStale) m(RISK_WEIGHTS.ORACLE_STALE);

    if (e.ratioDeviationBps > THRESHOLDS.RATIO_DEVIATION_CRITICAL_BPS) m(80);
    else if (e.ratioDeviationBps > THRESHOLDS.RATIO_DEVIATION_WARN_BPS) m(RISK_WEIGHTS.RATIO_DEVIATION);

    if (e.lpMintDiscrepancyBps > THRESHOLDS.LP_MINT_DISCREPANCY_WARN_BPS)
        m(RISK_WEIGHTS.HIGH_OUTPUT_DISCREPANCY);

    const riskLevel: RiskLevel =
        s >= 80 ? "CRITICAL" : s >= 30 ? "WARNING" : "SAFE";
    return { riskScore: s, riskLevel };
}

// ─── Error result ─────────────────────────────────────────────────────────────

function _errorResult(operationType: LiquidityOpType, reason: string): LiquidityOffChainResult {
    return {
        isSafe: false, riskLevel: "CRITICAL", riskScore: 100, operation: operationType,
        trace: {
            hasDangerousDelegateCall: false, delegateCallTarget: null,
            hasSelfDestruct: false,
            hasUnexpectedCreate: false, createAddresses: [],
            hasApprovalDrain: false, approvalDrainSpender: null,
            hasReentrancy: false, reentrancyAddress: null,
            hasOwnerSweep: false, sweepAmount: "0", sweepToken: null,
        },
        economic: {
            simulationReverted: true, revertReason: reason,
            actualAmountA: "0", actualAmountB: "0",
            actualLPMinted: "0", expectedLPMinted: "0", lpMintDiscrepancyBps: 0,
            excessTokenALost: "0", excessTokenBLost: "0", excessValueLostUSD: "0",
            actualReceivedA: "0", actualReceivedB: "0",
            pairAddress: "", lpTotalSupply: "0", reserveA: "0", reserveB: "0",
            isFirstDeposit: false,
            poolRatio: "0", oracleRatio: "0", ratioDeviationBps: 0,
            isRemovalFrozen: false, removalRevertReason: "", removalSimAmountA: "0", removalSimAmountB: "0",
            tokenAPriceUSD: "0", tokenBPriceUSD: "0",
            tokenAOracleStale: false, tokenBOracleStale: false,
            tokenAOracleAge: 0, tokenBOracleAge: 0,
        },
        routerVerified: false, pairVerified: false, tokenAVerified: false, tokenBVerified: false,
        simulatedAt: Math.floor(Date.now() / 1000), network: "arbitrum-mainnet",
    };
}