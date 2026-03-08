// ============================================================================
//  vaultLogic.ts — Off-chain CRE simulation for ERC4626 vaults (Arbitrum)
//
//  Operations covered:
//    deposit(assets, receiver)              → primaryOutput = shares minted
//    mint(shares, receiver)                 → primaryOutput = assets consumed
//    withdraw(assets, receiver, owner)      → primaryOutput = shares burned
//    redeem(shares, receiver, owner)        → primaryOutput = assets received
//
//  Each operation:
//    1. Reads pre-state (share price, preview values, asset/share balances)
//    2. Builds correct state overrides (asset balance for deposit/mint;
//       share balance + allowance for withdraw/redeem)
//    3. Runs evm.call with trace: true
//    4. Analyses trace (DELEGATECALL, SELFDESTRUCT, sweep, reentrancy, upgrade)
//    5. Decodes primary output and computes discrepancy vs preview
//    6. For entry operations (deposit/mint): simulates matching exit to detect honeypot
//    7. Reads post-state for share price drift
//    8. Runs Chainlink oracle check
//    9. Runs contract verification
// ============================================================================

import { ethers } from "ethers";
import {
    VaultOpType, VaultOffChainResult, VaultTraceFindings, VaultEconomicFindings,
    RiskLevel, RISK_WEIGHTS, THRESHOLDS,
} from "./common/types.js";
import { getTokenPrice } from "./common/chainlink.js";
import {
    findDangerousDelegateCall, findSelfDestruct, findUnexpectedCreates,
    findReentrancy, findApprovalDrain, findOwnerSweep, findUpgradeCall,
    decodeRevertReason,
} from "./common/traceAnalysis.js";
import {
    buildERC20BalanceOverride, buildERC20Override, buildERC20AllowanceOverride,
} from "./common/tokenOverrides.js";
import { checkContractVerified } from "./common/arbiscan.js";

// ─── ERC4626 interface fragments ──────────────────────────────────────────────

const VAULT_IFACE = new ethers.utils.Interface([
    "function asset() view returns (address)",
    "function decimals() view returns (uint8)",
    "function totalAssets() view returns (uint256)",
    "function totalSupply() view returns (uint256)",
    "function owner() view returns (address)",
    "function convertToAssets(uint256 shares) view returns (uint256)",
    "function convertToShares(uint256 assets) view returns (uint256)",
    "function previewDeposit(uint256 assets) view returns (uint256 shares)",
    "function previewMint(uint256 shares) view returns (uint256 assets)",
    "function previewWithdraw(uint256 assets) view returns (uint256 shares)",
    "function previewRedeem(uint256 shares) view returns (uint256 assets)",
    "function maxDeposit(address) view returns (uint256)",
    "function maxMint(address) view returns (uint256)",
    "function maxWithdraw(address) view returns (uint256)",
    "function maxRedeem(address) view returns (uint256)",
    "function deposit(uint256 assets, address receiver) returns (uint256 shares)",
    "function mint(uint256 shares, address receiver) returns (uint256 assets)",
    "function withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)",
    "function redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)",
]);

// ─── Main entry point ─────────────────────────────────────────────────────────

export const vaultLogic = async (runtime: any, context: any): Promise<VaultOffChainResult> => {
    const {
        opType,        // VaultOpType: "DEPOSIT" | "MINT" | "WITHDRAW" | "REDEEM"
        from,          // user wallet — also acts as owner for withdraw/redeem
        vaultAddress,
        amount,        // assets for deposit/withdraw; shares for mint/redeem (string, wei)
        data,          // ABI-encoded calldata built by the extension
        receiver,      // address to receive shares/assets
    } = context.data as {
        opType: VaultOpType;
        from: string;
        vaultAddress: string;
        amount: string;
        data: string;
        receiver?: string;
    };

    const op      = opType as VaultOpType;
    const evm     = runtime.capabilities.evm("arbitrum-mainnet");
    const http    = runtime.capabilities.http;
    const amountBN = ethers.BigNumber.from(amount);
    const rcvr    = receiver ?? from;
    const bpsMultiplier = 10000;

    // ─── 1. Discover asset ────────────────────────────────────────────────────

    const assetAddress: string = await evm.read({ to: vaultAddress, func: "asset()" });
    const [assetDecimals, vaultOwner] = await Promise.all([
        evm.read({ to: assetAddress, func: "decimals()" }).then(Number),
        evm.read({ to: vaultAddress, func: "owner()" }).catch(() => ethers.constants.AddressZero),
    ]);

    // ─── 2. Read preview + share price BEFORE operation ──────────────────────

    const [previewResult, sharePriceBeforeBN] = await Promise.all([
        _readPreview(evm, vaultAddress, op, amountBN, from),
        _readSharePrice(evm, vaultAddress),
    ]);

    // ─── 3. Build state overrides ─────────────────────────────────────────────

    const stateOverrides = _buildOverrides(op, {
        assetAddress,
        vaultAddress,
        from,
        amountBN,
        previewResult,
        vaultOwner,
    });

    // ─── 4. Run primary simulation ────────────────────────────────────────────

    let simulation: any;
    try {
        simulation = await evm.call({
            from,
            to:    vaultAddress,
            data,
            trace: true,
            stateOverrides,
        });
    } catch (err: any) {
        return _errorResult(op, `SIMULATION_EXCEPTION:${err?.message ?? "unknown"}`);
    }

    const simReverted  = simulation.status === "0x0";
    const revertReason = simReverted ? decodeRevertReason(simulation.data ?? "0x") : "";

    // ─── 5. Decode primary output ─────────────────────────────────────────────

    let primaryOutput = ethers.BigNumber.from(0);
    if (!simReverted && simulation.data && simulation.data !== "0x") {
        try {
            const [val] = ethers.utils.defaultAbiCoder.decode(["uint256"], simulation.data);
            primaryOutput = val as ethers.BigNumber;
        } catch { /* leave 0 */ }
    }

    // ─── 6. Output discrepancy in BPS ─────────────────────────────────────────
    // preview - actual discrepancy
    const primaryExpected = previewResult;
    let outputDiscrepancyBps = 0;
    if (!primaryExpected.isZero() && !primaryOutput.isZero()) {
        const diff = primaryExpected.gt(primaryOutput)
            ? primaryExpected.sub(primaryOutput)
            : primaryOutput.sub(primaryExpected);
        outputDiscrepancyBps = diff.mul(bpsMultiplier).div(primaryExpected).toNumber();          // -ve /+ve aspect not considered , just absolute differnece only .
    }

    // ─── 7. mint() excess asset pull detection ────────────────────────────────
    // For mint: user approves, vault pulls `previewMint(shares)` of assets.
    // If vault actually pulled MORE than previewMint, that's theft.
    // We measure by reading the user's asset balance after (override gives them 2× previewMint).
    let actualAssetPull  = ethers.BigNumber.from(0);
    let excessPullBps    = 0;

    if (op === "MINT" && !simReverted) {
        // primaryOutput for mint = assets consumed (returned by mint())
        actualAssetPull = primaryOutput;
        if (!previewResult.isZero() && actualAssetPull.gt(previewResult)) {
            const excess = actualAssetPull.sub(previewResult);
            excessPullBps = excess.mul(bpsMultiplier).div(previewResult).toNumber();
        }
    }

    // ─── 8. Trace analysis ────────────────────────────────────────────────────

    const trace = simulation.trace ?? [];

    // For vault, the contract itself is the safe DELEGATECALL target (proxy pattern).
    // We only flag DELEGATECALLs to addresses beyond the vault.
    const delegateResult  = findDangerousDelegateCall(trace, [vaultAddress]);
    const hasSelfDestruct = findSelfDestruct(trace);
    const creates         = findUnexpectedCreates(trace);
    const reentrant       = findReentrancy(trace);
    const upgradeResult   = findUpgradeCall(trace);
    const sweepResult     = findOwnerSweep(trace, vaultOwner);

    // Legitimate approve targets: vault itself, asset contract
    const approvalResult = findApprovalDrain(trace, [vaultAddress, assetAddress, from, rcvr]);

    const traceFindings: VaultTraceFindings = {
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
        hasUpgradeCall:           upgradeResult.found,
        upgradeTarget:            upgradeResult.target,
    };

    // ─── 9. Share price AFTER operation ──────────────────────────────────────
    // Re-read in forked state. Only meaningful for entry ops.
    const sharePriceAfterBN = await _readSharePrice(evm, vaultAddress);
    let sharePriceDriftBps  = 0;
    if (!sharePriceBeforeBN.isZero() && !sharePriceAfterBN.isZero()) {
        const diff = sharePriceBeforeBN.gt(sharePriceAfterBN)
            ? sharePriceBeforeBN.sub(sharePriceAfterBN)
            : sharePriceAfterBN.sub(sharePriceBeforeBN);
        sharePriceDriftBps = diff.mul(bpsMultiplier).div(sharePriceBeforeBN).toNumber();
    }

    // ─── 10. Exit/entry honeypot check ───────────────────────────────────────
    // deposit → simulate redeem(shares received)
    // mint    → simulate redeem(shares requested)
    // withdraw/redeem → no check needed (they ARE the exit)
    let isExitFrozen     = false;
    let exitRevertReason = "";
    let exitSimulatedOut = ethers.BigNumber.from(0);

    if ((op === "DEPOSIT" || op === "MINT") && !simReverted) {
        const sharesToRedeem =
            op === "DEPOSIT" ? primaryOutput :   // shares received from deposit
            amountBN;                            // shares requested in mint

        if (sharesToRedeem.gt(0)) {
            const redeemData = VAULT_IFACE.encodeFunctionData("redeem", [
                sharesToRedeem, rcvr, from,
            ]);

            // Give `from` the shares so the redeem sim has something to burn
            const shareOverride = buildERC20Override({
                tokenAddress: vaultAddress,
                user:         from,
                amount:       sharesToRedeem.mul(2),
                spender:      vaultAddress,
            });

            // Also give vault some assets to return
            const assetReserve = buildERC20BalanceOverride(
                assetAddress, vaultAddress, amountBN.mul(10)
            );

            try {
                const redeemSim = await evm.call({
                    from,
                    to:    vaultAddress,
                    data:  redeemData,
                    trace: false,
                    stateOverrides: {
                        [vaultAddress]: shareOverride,
                        [assetAddress]: assetReserve,
                    },
                });
                if (redeemSim.status === "0x0") {
                    isExitFrozen     = true;
                    exitRevertReason = decodeRevertReason(redeemSim.data ?? "0x");
                } else if (redeemSim.data && redeemSim.data !== "0x") {
                    const [v] = ethers.utils.defaultAbiCoder.decode(["uint256"], redeemSim.data);
                    exitSimulatedOut = v as ethers.BigNumber;
                }
            } catch (err: any) {
                isExitFrozen     = true;
                exitRevertReason = `REDEEM_SIM_EXCEPTION:${err?.message ?? "unknown"}`;
            }
        }
    }

    // ─── 11. Oracle ───────────────────────────────────────────────────────────

    const assetOracle = await getTokenPrice(evm, assetAddress);

    // ─── 12. Verification ─────────────────────────────────────────────────────

    const [vaultVerif, assetVerif] = await Promise.all([
        checkContractVerified(http, vaultAddress),
        checkContractVerified(http, assetAddress),
    ]);

    // ─── 13. Assemble result ─────────────────────────────────────────────────

    const economicFindings: VaultEconomicFindings = {
        simulationReverted:   simReverted,
        revertReason,
        primaryOutput:        primaryOutput.toString(),
        primaryExpected:      primaryExpected.toString(),
        outputDiscrepancyBps,
        sharePriceBefore:     sharePriceBeforeBN.toString(),
        sharePriceAfter:      sharePriceAfterBN.toString(),
        sharePriceDriftBps,
        isExitFrozen,
        exitRevertReason,
        exitSimulatedOut:     exitSimulatedOut.toString(),
        actualAssetPull:      actualAssetPull.toString(),
        excessPullBps,
        assetPriceUSD:        assetOracle.priceUSD.toString(),
        assetOracleStale:     assetOracle.isStale,
        assetOracleAge:       assetOracle.ageSeconds,
    };

    const { riskScore, riskLevel } = _computeVaultRisk(traceFindings, economicFindings);

    const isSafe =
        riskLevel === "SAFE"                       &&
        !simReverted                               &&
        !traceFindings.hasDangerousDelegateCall    &&
        !traceFindings.hasSelfDestruct             &&
        !traceFindings.hasOwnerSweep               &&
        !traceFindings.hasApprovalDrain            &&
        !traceFindings.hasUpgradeCall              &&
        !economicFindings.isExitFrozen;

    return {
        isSafe, riskLevel, riskScore, operation: op,
        trace: traceFindings, economic: economicFindings,
        vaultVerified: vaultVerif.isVerified,
        assetVerified: assetVerif.isVerified,
        simulatedAt:   Math.floor(Date.now() / 1000),
        network:       "arbitrum-mainnet",
    };
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function _readPreview(
    evm:          any,
    vaultAddress: string,
    op:           VaultOpType,
    amount:       ethers.BigNumber,
    user:         string
): Promise<ethers.BigNumber> {
    const fnMap: Record<VaultOpType, string> = {
        DEPOSIT:  `previewDeposit(uint256)`,
        MINT:     `previewMint(uint256)`,
        WITHDRAW: `previewWithdraw(uint256)`,
        REDEEM:   `previewRedeem(uint256)`,
    };
    try {
        return ethers.BigNumber.from(
            await evm.read({ to: vaultAddress, func: fnMap[op], args: [amount] })
        );
    } catch {
        return ethers.BigNumber.from(0);
    }
}

async function _readSharePrice(evm: any, vaultAddress: string): Promise<ethers.BigNumber> {
    try {
        return ethers.BigNumber.from(
            await evm.read({
                to:   vaultAddress,
                func: "convertToAssets(uint256)",
                args: [ethers.utils.parseUnits("1", 18)],
            })
        );
    } catch {
        return ethers.BigNumber.from(0);
    }
}

function _buildOverrides(
    op:  VaultOpType,
    p:   {
        assetAddress: string;
        vaultAddress: string;
        from:         string;
        amountBN:     ethers.BigNumber;
        previewResult: ethers.BigNumber;
        vaultOwner:   string;
    }
): Record<string, any> {
    const overrides: Record<string, any> = {};

    if (op === "DEPOSIT") {
        // User needs asset tokens; vault will pull them via transferFrom
        overrides[p.assetAddress] = buildERC20Override({
            tokenAddress: p.assetAddress,
            user:         p.from,
            amount:       p.amountBN.mul(2),
            spender:      p.vaultAddress,
        });
    }

    if (op === "MINT") {
        // vault calls transferFrom(user, vault, previewMint(shares)) of assets
        // Give user 2× previewMint so there's headroom for over-pull detection
        const assetNeeded = p.previewResult.isZero()
            ? p.amountBN.mul(2)
            : p.previewResult.mul(2);
        overrides[p.assetAddress] = buildERC20Override({
            tokenAddress: p.assetAddress,
            user:         p.from,
            amount:       assetNeeded,
            spender:      p.vaultAddress,
        });
    }

    if (op === "WITHDRAW") {
        // vault burns previewWithdraw(assets) shares from user
        // Give user sufficient shares + allowance for the vault to burn them
        const sharesToCover = p.previewResult.isZero()
            ? p.amountBN
            : p.previewResult.mul(12).div(10); // 20% headroom
        overrides[p.vaultAddress] = buildERC20Override({
            tokenAddress: p.vaultAddress,
            user:         p.from,
            amount:       sharesToCover,
            spender:      p.vaultAddress,   // vault burns via transferFrom(owner, vault, shares)
        });
        // Also give vault assets to pay out
        overrides[p.assetAddress] = buildERC20BalanceOverride(
            p.assetAddress, p.vaultAddress, p.amountBN.mul(10)
        );
    }

    if (op === "REDEEM") {
        // User burns exact `amountBN` shares
        overrides[p.vaultAddress] = buildERC20Override({
            tokenAddress: p.vaultAddress,
            user:         p.from,
            amount:       p.amountBN.mul(2),
            spender:      p.vaultAddress,
        });
        // Give vault assets to pay out (previewRedeem is expected output)
        const assetPayout = p.previewResult.isZero() ? p.amountBN : p.previewResult.mul(2);
        overrides[p.assetAddress] = buildERC20BalanceOverride(
            p.assetAddress, p.vaultAddress, assetPayout.mul(5)
        );
    }

    return overrides;
}

// ─── Risk scoring ─────────────────────────────────────────────────────────────

function _computeVaultRisk(
    t: VaultTraceFindings,
    e: VaultEconomicFindings
): { riskScore: number; riskLevel: RiskLevel } {
    let s = 0;
    const m = (w: number) => { s = Math.max(s, w); };

    if (t.hasDangerousDelegateCall)                    m(RISK_WEIGHTS.DANGEROUS_DELEGATECALL);
    if (t.hasSelfDestruct)                             m(RISK_WEIGHTS.SELFDESTRUCT);
    if (t.hasOwnerSweep)                               m(RISK_WEIGHTS.OWNER_SWEEP);
    if (t.hasApprovalDrain)                            m(RISK_WEIGHTS.APPROVAL_DRAIN);
    if (t.hasUpgradeCall)                              m(RISK_WEIGHTS.UPGRADE_CALL);
    if (e.isExitFrozen)                                m(RISK_WEIGHTS.EXIT_FROZEN);
    if (e.simulationReverted)                          m(RISK_WEIGHTS.SIMULATION_REVERT);
    if (t.hasUnexpectedCreate)                         m(RISK_WEIGHTS.UNEXPECTED_CREATE);
    if (t.hasReentrancy)                               m(RISK_WEIGHTS.REENTRANCY);
    if (e.excessPullBps > THRESHOLDS.EXCESS_PULL_WARN_BPS) m(RISK_WEIGHTS.EXCESS_PULL);
    if (e.outputDiscrepancyBps > THRESHOLDS.SHARE_DISCREPANCY_WARN_BPS)
                                                       m(RISK_WEIGHTS.HIGH_OUTPUT_DISCREPANCY);
    if (e.sharePriceDriftBps > THRESHOLDS.SHARE_PRICE_DRIFT_WARN_BPS)
                                                       m(RISK_WEIGHTS.SHARE_PRICE_DRIFT);
    if (e.assetOracleStale)                            m(RISK_WEIGHTS.ORACLE_STALE);

    const riskLevel: RiskLevel =
        s >= 80 ? "CRITICAL" : s >= 30 ? "WARNING" : "SAFE";
    return { riskScore: s, riskLevel };
}

// ─── Error result ─────────────────────────────────────────────────────────────

function _errorResult(op: VaultOpType, reason: string): VaultOffChainResult {
    return {
        isSafe: false, riskLevel: "CRITICAL", riskScore: 100, operation: op,
        trace: {
            hasDangerousDelegateCall: false, delegateCallTarget: null,
            hasSelfDestruct: false,
            hasUnexpectedCreate: false, createAddresses: [],
            hasApprovalDrain: false, approvalDrainSpender: null,
            hasReentrancy: false, reentrancyAddress: null,
            hasOwnerSweep: false, sweepAmount: "0", sweepToken: null,
            hasUpgradeCall: false, upgradeTarget: null,
        },
        economic: {
            simulationReverted: true, revertReason: reason,
            primaryOutput: "0", primaryExpected: "0", outputDiscrepancyBps: 0,
            sharePriceBefore: "0", sharePriceAfter: "0", sharePriceDriftBps: 0,
            isExitFrozen: false, exitRevertReason: "", exitSimulatedOut: "0",
            actualAssetPull: "0", excessPullBps: 0,
            assetPriceUSD: "0", assetOracleStale: false, assetOracleAge: 0,
        },
        vaultVerified: false, assetVerified: false,
        simulatedAt: Math.floor(Date.now() / 1000), network: "arbitrum-mainnet",
    };
}