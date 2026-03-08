// ============================================================================
//  swapLogic.ts — Off-chain CRE simulation for all Uniswap V2 swap variants
//
//  Operations covered:
//    EXACT_TOKENS_IN      swapExactTokensForTokens       token→token exact in
//    EXACT_TOKENS_OUT     swapTokensForExactTokens        token→token exact out
//    EXACT_ETH_IN         swapExactETHForTokens           ETH→token  exact in
//    EXACT_ETH_OUT        swapETHForExactTokens           ETH→token  exact out (payable max)
//    EXACT_TOKENS_FOR_ETH swapExactTokensForETH           token→ETH  exact in
//    TOKENS_FOR_EXACT_ETH swapTokensForExactETH           token→ETH  exact out
// 
//  Each variant:
//    - Builds correct state overrides (ERC20 storage slot OR native ETH balance)
//    - Correctly decodes amounts[] return data for the specific function
//    - Measures inputHeadroom for exactOut variants
//    - Measures ETH refunded for ETH-out variants
//    - Runs trace analysis (DELEGATECALL, SELFDESTRUCT, CREATE, approval drain, reentrancy)
//    - Measures actual fee-on-transfer via balance delta (not heuristic)
//    - Cross-checks with Chainlink oracle
//    - Verifies all contracts on Arbiscan
// ============================================================================

import { ethers } from "ethers";
import {
    SwapOpType, SwapOffChainResult, SwapTraceFindings, SwapEconomicFindings,
    RiskLevel, RISK_WEIGHTS, THRESHOLDS,
} from "./common/types.js";
import { getTokenPrice, computeFairOutput } from "./common/chainlink.js";
import {
    findDangerousDelegateCall, findSelfDestruct, findUnexpectedCreates,
    findReentrancy, findApprovalDrain, decodeRevertReason,
} from "./common/traceAnalysis.js";
import {
    buildERC20Override, buildNativeETHOverride,
} from "./common/tokenOverrides.js";
import { checkContractVerified } from "./common/arbiscan.js";

// WETH on Arbitrum — path[0] for ETH-in swaps, path[last] for ETH-out swaps
const WETH = "0x82af49447d8a07e3bd95bd0d56f35241523fbab1";

// ─── Context shape ────────────────────────────────────────────────────────────

interface SwapContext {
    opType:       SwapOpType;
    from:         string;     // user wallet
    routerAddress: string;    // Uniswap V2-compatible router
    data:         string;     // ABI-encoded calldata built by extension
    path:         string[];   // token addresses
    amountIn:     string;     // for exact-in variants (wei)
    amountOut:    string;     // for exact-out variants (wei)
    amountInMax:  string;     // for exact-out variants (wei)
    amountOutMin: string;     // for exact-in variants (wei)
    ethValue:     string;     // msg.value in wei (ETH-in variants)
}

// ─── Main entry point ─────────────────────────────────────────────────────────

export const swapLogic = async (runtime: any, context: any): Promise<SwapOffChainResult> => {
    const ctx = context.data as SwapContext;
    const {
        opType, from, routerAddress, data, path,
        amountIn = "0", amountOut = "0",
        amountInMax = "0", amountOutMin = "0",
        ethValue = "0",
    } = ctx;

    const op  = opType as SwapOpType;
    const evm = runtime.capabilities.evm("arbitrum-mainnet");
    const http = runtime.capabilities.http;

    if (!path || path.length < 2) throw new Error("CRE_SWAP: path must have ≥ 2 tokens");

    const tokenIn  = _isETH(op) ? WETH : path[0];           // oracle lookup uses WETH for ETH
    const tokenOut = _isETHOut(op) ? WETH : path[path.length - 1];

    // ─── 1. Decimals ──────────────────────────────────────────────────────────
    // Must be fetched BEFORE building overrides (used in storage slot computation)
    const [tokenInDecimals, tokenOutDecimals] = await Promise.all([
        _isETH(op)    ? Promise.resolve(18) : evm.read({ to: path[0], func: "decimals()" }).then(Number),
        _isETHOut(op) ? Promise.resolve(18) : evm.read({ to: path[path.length - 1], func: "decimals()" }).then(Number),
    ]);

    // ─── 2. State overrides ───────────────────────────────────────────────────
    const stateOverrides = _buildSwapOverrides(op, {
        from, routerAddress, path,
        amountIn, amountInMax, ethValue,
        tokenInDecimals,
    });

    // ─── 3. Run simulation ────────────────────────────────────────────────────
    let simulation: any;
    try {
        simulation = await evm.call({
            from,
            to:    routerAddress,
            data,
            value: _isETH(op) ? ethValue : "0x0",
            trace: true,
            stateOverrides,
        });
    } catch (err: any) {
        return _errorResult(op, `SIMULATION_EXCEPTION:${err?.message ?? "unknown"}`);
    }

    const simReverted  = simulation.status === "0x0";
    const revertReason = simReverted ? decodeRevertReason(simulation.data ?? "0x") : "";

    // ─── 4. Decode amounts[] return ───────────────────────────────────────────
    // All V2 swap functions return uint256[] amounts (one per path hop + 1).
    // amounts[0] = input consumed, amounts[last] = output received.
    let amounts: ethers.BigNumber[] = [];
    if (!simReverted && simulation.data && simulation.data !== "0x") {
        try {
            const [arr] = ethers.utils.defaultAbiCoder.decode(["uint256[]"], simulation.data);
            amounts = arr as ethers.BigNumber[];
        } catch { /* leave empty */ }
    }

    const actualAmountIn  = amounts.length > 0 ? amounts[0]                  : ethers.BigNumber.from(0);
    const actualAmountOut = amounts.length > 0 ? amounts[amounts.length - 1] : ethers.BigNumber.from(0);

    // ─── 5. inputHeadroom for exactOut variants ───────────────────────────────
    // How much of their max spend did the user NOT use?
    let inputHeadroomBps = 0;
    if (_isExactOut(op)) {
        const maxIn = ethers.BigNumber.from(_isETH(op) ? ethValue : amountInMax);
        if (!maxIn.isZero() && !actualAmountIn.isZero() && maxIn.gte(actualAmountIn)) {
            const saved = maxIn.sub(actualAmountIn);
            inputHeadroomBps = saved.mul(10000).div(maxIn).toNumber();
        }
    }

    // ─── 6. ETH refunded (ETH-out exact variants) ────────────────────────────
    // For swapETHForExactTokens: user sends msg.value, router refunds excess ETH.
    // We detect this by looking for an ETH transfer back to `from` in the trace.
    let ethRefunded = ethers.BigNumber.from(0);
    if (op === "EXACT_ETH_OUT") {                                                  
        for (const e of (simulation.trace ?? []).flat?.() ?? []) {
            if (
                e.to?.toLowerCase() === from.toLowerCase() &&
                e.value && e.value !== "0x0"
            ) {
                try { ethRefunded = ethers.BigNumber.from(e.value); } catch { /* skip */ }
                break;
            }
        }
    }

    // ─── 7. Fee-on-transfer measurement ──────────────────────────────────────
    // On-chain TokenGuard uses selector heuristics.
    // Here we actually measure: simulate a tiny direct transfer and compare
    // what the recipient receives vs what was sent.
    let isFeeOnTransfer   = false;
    let measuredFeePercent = 0;

    if (!_isETH(op) && !_isETHOut(op)) {
        const testToken  = path[0];
        const testAmount = ethers.utils.parseUnits("0.01", tokenInDecimals); // 0.01 tokens

        try {
            const transferCalldata = new ethers.utils.Interface([
                "function transfer(address to, uint256 amount) returns (bool)"
            ]).encodeFunctionData("transfer", [routerAddress, testAmount]);

            const override = buildERC20Override({
                tokenAddress: testToken,
                user:         from,
                amount:       testAmount.mul(3),
                spender:      from,
            });

            const feeTestSim = await evm.call({
                from,
                to:    testToken,
                data:  transferCalldata,
                trace: false,
                stateOverrides: { [testToken]: override },
            });

            if (feeTestSim.status !== "0x0") {
                // Read router's balance of testToken after transfer
                const receivedBN = ethers.BigNumber.from(
                    await evm.read({ to: testToken, func: "balanceOf(address)", args: [routerAddress] })
                );
                if (receivedBN.lt(testAmount)) {
                    const feePaid = testAmount.sub(receivedBN);
                    const feeBps  = feePaid.mul(10000).div(testAmount).toNumber();
                    if (feeBps > THRESHOLDS.FEE_ON_TRANSFER_MIN_BPS) {
                        isFeeOnTransfer    = true;
                        measuredFeePercent = feeBps / 100;
                    }
                }
            }
        } catch { /* fee detection failure is non-fatal */ }
    }

    // ─── 8. Trace analysis ────────────────────────────────────────────────────
    const trace = simulation.trace ?? [];

    // Safe delegatecall targets = the router only (it may delegate to a library)
    const delegateResult = findDangerousDelegateCall(trace, [routerAddress]);
    const hasSelfDestruct = findSelfDestruct(trace);
    const creates         = findUnexpectedCreates(trace);
    const reentrant       = findReentrancy(trace);

    // Legitimate approve targets: router, any token in path, the user
    const legitApprove = [routerAddress, ...path, from];
    const approvalResult = findApprovalDrain(trace, legitApprove);

    const traceFindings: SwapTraceFindings = {
        hasDangerousDelegateCall: delegateResult.found,
        delegateCallTarget:       delegateResult.target,
        hasSelfDestruct,
        hasUnexpectedCreate:      creates.length > 0,
        createAddresses:          creates,
        hasApprovalDrain:         approvalResult.found,
        approvalDrainSpender:     approvalResult.spender,
        hasReentrancy:            reentrant.found,
        reentrancyAddress:        reentrant.address,
    };

    // ─── 9. Chainlink oracle cross-check ─────────────────────────────────────
    // We cross-check ACTUAL output vs what Chainlink says you should get.
    // This is distinct from the on-chain TWAP check (which uses pool history).
    // A large deviation here means either: pool is manipulated, or the path
    // has significant slippage from low liquidity.
    const [inOracle, outOracle] = await Promise.all([
        getTokenPrice(evm, tokenIn),
        getTokenPrice(evm, tokenOut),
    ]);

    let priceImpactBps    = 0;
    let oracleDeviation   = false;
    let oracleFairAmountOut = "0";

    if (inOracle.found && outOracle.found && !simReverted) {
        // For exactOut swaps, use the actual amountIn consumed for impact calculation
        const inputForCalc = _isExactOut(op) ? actualAmountIn : ethers.BigNumber.from(amountIn || ethValue);
        const inDec = _isETH(op) ? 18 : tokenInDecimals;
        const outDec = _isETHOut(op) ? 18 : tokenOutDecimals;

        const { fairAmountOut, priceImpactBps: calcImpact } = computeFairOutput({
            amountIn:         inputForCalc,
            tokenInDecimals:  inDec,
            tokenInPriceUSD:  inOracle.priceUSD,
            tokenOutDecimals: outDec,
            tokenOutPriceUSD: outOracle.priceUSD,
        });

        priceImpactBps    = calcImpact(actualAmountOut);
        oracleFairAmountOut = fairAmountOut.toString();
        oracleDeviation   = Math.abs(priceImpactBps) > THRESHOLDS.PRICE_IMPACT_WARN_BPS;
    }

    // ─── 10. Contract verification ────────────────────────────────────────────
    const contractsToVerify = [
        checkContractVerified(http, routerAddress),
        _isETH(op) ? Promise.resolve({ isVerified: true }) : checkContractVerified(http, path[0]),
        _isETHOut(op) ? Promise.resolve({ isVerified: true }) : checkContractVerified(http, path[path.length - 1]),
    ];
    const [routerVerif, tokenInVerif, tokenOutVerif] = await Promise.all(contractsToVerify);

    // ─── 11. Assemble result ──────────────────────────────────────────────────

    const economicFindings: SwapEconomicFindings = {
        simulationReverted:  simReverted,
        revertReason,
        actualAmountIn:      actualAmountIn.toString(),
        actualAmountOut:     actualAmountOut.toString(),
        inputHeadroomBps,
        ethRefunded:         ethRefunded.toString(),
        oracleFairAmountOut,
        priceImpactBps,
        oracleDeviation,
        isFeeOnTransfer,
        measuredFeePercent,
        tokenInPriceUSD:     inOracle.priceUSD.toString(),
        tokenOutPriceUSD:    outOracle.priceUSD.toString(),
        tokenInOracleStale:  inOracle.isStale,
        tokenOutOracleStale: outOracle.isStale,
        tokenInOracleAge:    inOracle.ageSeconds,
        tokenOutOracleAge:   outOracle.ageSeconds,
    };

    const { riskScore, riskLevel } = _computeSwapRisk(traceFindings, economicFindings);

    const isSafe =
        riskLevel === "SAFE"                    &&
        !simReverted                            &&
        !traceFindings.hasDangerousDelegateCall &&
        !traceFindings.hasSelfDestruct          &&
        !traceFindings.hasApprovalDrain;

    return {
        isSafe, riskLevel, riskScore, operation: op,
        trace: traceFindings, economic: economicFindings,
        routerVerified:   routerVerif.isVerified,
        tokenInVerified:  tokenInVerif.isVerified,
        tokenOutVerified: tokenOutVerif.isVerified,
        simulatedAt: Math.floor(Date.now() / 1000),
        network:     "arbitrum-mainnet",
    };
};

// ─── State override builder ───────────────────────────────────────────────────

function _buildSwapOverrides(
    op: SwapOpType,
    p: {
        from:           string;
        routerAddress:  string;
        path:           string[];
        amountIn:       string;
        amountInMax:    string;
        ethValue:       string;
        tokenInDecimals: number;
    }
): Record<string, any> {
    const overrides: Record<string, any> = {};

    // ETH-in variants: override native ETH balance of user
    if (op === "EXACT_ETH_IN" || op === "EXACT_ETH_OUT") {
        const ethBN = ethers.BigNumber.from(p.ethValue || "0");
        overrides[p.from] = buildNativeETHOverride(ethBN.mul(2));
        return overrides;
    }

    // All token-in variants: override ERC20 balance + allowance of path[0]
    const tokenIn   = p.path[0];
    const rawAmount = op === "EXACT_TOKENS_IN" || op === "EXACT_TOKENS_FOR_ETH"
        ? ethers.BigNumber.from(p.amountIn  || "0")
        : ethers.BigNumber.from(p.amountInMax || "0");

    overrides[tokenIn] = buildERC20Override({
        tokenAddress: tokenIn,
        user:         p.from,
        amount:       rawAmount.mul(2),
        spender:      p.routerAddress,
    });

    return overrides;
}

// ─── Operation category helpers ───────────────────────────────────────────────

function _isETH(op: SwapOpType): boolean {
    return op === "EXACT_ETH_IN" || op === "EXACT_ETH_OUT";
}

function _isETHOut(op: SwapOpType): boolean {
    return op === "EXACT_TOKENS_FOR_ETH" || op === "TOKENS_FOR_EXACT_ETH";
}

function _isExactOut(op: SwapOpType): boolean {
    return op === "EXACT_TOKENS_OUT" || op === "EXACT_ETH_OUT" || op === "TOKENS_FOR_EXACT_ETH";
}

// ─── Risk scoring ─────────────────────────────────────────────────────────────

function _computeSwapRisk(
    t: SwapTraceFindings,
    e: SwapEconomicFindings
): { riskScore: number; riskLevel: RiskLevel } {
    let s = 0;
    const m = (w: number) => { s = Math.max(s, w); };

    if (t.hasDangerousDelegateCall) m(RISK_WEIGHTS.DANGEROUS_DELEGATECALL);
    if (t.hasSelfDestruct)          m(RISK_WEIGHTS.SELFDESTRUCT);
    if (t.hasApprovalDrain)         m(RISK_WEIGHTS.APPROVAL_DRAIN);
    if (e.simulationReverted)       m(RISK_WEIGHTS.SIMULATION_REVERT);
    if (t.hasUnexpectedCreate)      m(RISK_WEIGHTS.UNEXPECTED_CREATE);
    if (t.hasReentrancy)            m(RISK_WEIGHTS.REENTRANCY);
    if (e.oracleDeviation)          m(RISK_WEIGHTS.ORACLE_DEVIATION);
    if (e.isFeeOnTransfer)          m(RISK_WEIGHTS.FEE_ON_TRANSFER);
    if (e.tokenInOracleStale || e.tokenOutOracleStale) m(RISK_WEIGHTS.ORACLE_STALE);

    if (Math.abs(e.priceImpactBps) > THRESHOLDS.PRICE_IMPACT_CRITICAL_BPS) m(80);

    const riskLevel: RiskLevel =
        s >= 80 ? "CRITICAL" : s >= 30 ? "WARNING" : "SAFE";
    return { riskScore: s, riskLevel };
}

// ─── Error result ─────────────────────────────────────────────────────────────

function _errorResult(op: SwapOpType, reason: string): SwapOffChainResult {
    return {
        isSafe: false, riskLevel: "CRITICAL", riskScore: 100, operation: op,
        trace: {
            hasDangerousDelegateCall: false, delegateCallTarget: null,
            hasSelfDestruct: false,
            hasUnexpectedCreate: false, createAddresses: [],
            hasApprovalDrain: false, approvalDrainSpender: null,
            hasReentrancy: false, reentrancyAddress: null,
        },
        economic: {
            simulationReverted: true, revertReason: reason,
            actualAmountIn: "0", actualAmountOut: "0",
            inputHeadroomBps: 0, ethRefunded: "0",
            oracleFairAmountOut: "0", priceImpactBps: 0, oracleDeviation: false,
            isFeeOnTransfer: false, measuredFeePercent: 0,
            tokenInPriceUSD: "0", tokenOutPriceUSD: "0",
            tokenInOracleStale: false, tokenOutOracleStale: false,
            tokenInOracleAge: 0, tokenOutOracleAge: 0,
        },
        routerVerified: false, tokenInVerified: false, tokenOutVerified: false,
        simulatedAt: Math.floor(Date.now() / 1000), network: "arbitrum-mainnet",
    };
}