// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    ExtendedEconomicData,
    PolicyRiskCategory,
    PolicyKind,
    PolicyNormalizedOffChainResult,
    PolicyCoreView,
    PolicyOffChainView,
    PolicyOnChainPack,
    PolicyTokenPack,
    PolicyTokenFlagsView
} from "../types/OnChainTypes.sol";
import {LiquidityOffChainResult, LiquidityOpType} from "../types/OffChainTypes.sol";
import {TokenGuardResult, LiquidityV2GuardResult} from "../types/OnChainTypes.sol";
import {BaseRiskPolicy, EnhancedCoreView} from "./BaseRiskPolicy.sol";

/// @notice Human-readable liquidity on-chain findings decoded from a packed report.
struct LiquidityV2OnChainView {
    bool routerNotTrusted;
    bool pairNotExists;
    bool zeroLiquidity;
    bool lowLiquidity;
    bool lowLpSupply;
    bool firstDepositorRisk;
    bool severeImbalance;
    bool kInvariantBroken;
    bool poolTooNew;
    bool amountRatioDeviation;
    bool highLpImpact;
    bool flashloanRisk;
    bool zeroLpOut;
    bool zeroAmountsOut;
    bool dustLp;
}

/// @notice Fully decoded liquidity risk report view returned by the policy.
struct LiquidityV2DecodedRiskReport {
    PolicyCoreView core;
    PolicyOffChainView offChain;
    PolicyTokenFlagsView tokenRisk;
    EnhancedCoreView enhancedView;
    LiquidityOpType operation;
    LiquidityV2OnChainView onChain;
}

/**
 * @author Sourav-IITBPL
 * @notice Risk policy for evaluating Uniswap V2-style liquidity operations into packed reports.
 */
contract LiquidityV2RiskPolicy is BaseRiskPolicy {
    uint8 internal constant FLAG_ROUTER_NOT_TRUSTED = 0;
    uint8 internal constant FLAG_PAIR_NOT_EXISTS = 1;
    uint8 internal constant FLAG_ZERO_LIQUIDITY = 2;
    uint8 internal constant FLAG_LOW_LIQUIDITY = 3;
    uint8 internal constant FLAG_LOW_LP_SUPPLY = 4;
    uint8 internal constant FLAG_FIRST_DEPOSITOR_RISK = 5;
    uint8 internal constant FLAG_SEVERE_IMBALANCE = 6;
    uint8 internal constant FLAG_K_INVARIANT_BROKEN = 7;
    uint8 internal constant FLAG_POOL_TOO_NEW = 8;
    uint8 internal constant FLAG_AMOUNT_RATIO_DEVIATION = 9;
    uint8 internal constant FLAG_HIGH_LP_IMPACT = 10;
    uint8 internal constant FLAG_FLASHLOAN_RISK = 11;
    uint8 internal constant FLAG_ZERO_LP_OUT = 12;
    uint8 internal constant FLAG_ZERO_AMOUNTS_OUT = 13;
    uint8 internal constant FLAG_DUST_LP = 14;

    /**
     * @notice Full evaluation with token-level analysis.
     *
     * @param offChainData  ABI-encoded LiquidityOffChainResult from CRE simulation.
     * @param onChainData   Guard check result (flag booleans).
     * @param operation     LiquidityOpType: ADD | ADD_ETH | REMOVE | REMOVE_ETH.
     * @return packedReport 256-bit packed report.
     */
    function evaluate(bytes calldata offChainData, LiquidityV2GuardResult memory onChainData, LiquidityOpType operation)
        external
        pure
        returns (uint256 packedReport)
    {
        return _evaluatePacked(
            offChainData, onChainData, operation, _tokenPack(onChainData.tokenAResult, onChainData.tokenBResult)
        );
    }

    /**
     * @notice Evaluates and immediately decodes a liquidity risk report.
     * @param offChainData ABI-encoded LiquidityOffChainResult from CRE simulation.
     * @param onChainData Liquidity guard result used for evaluation.
     * @param operation Liquidity operation being evaluated.
     * @return report Decoded liquidity risk report.
     */
    function previewReport(
        bytes calldata offChainData,
        LiquidityV2GuardResult calldata onChainData,
        LiquidityOpType operation
    ) external pure returns (LiquidityV2DecodedRiskReport memory report) {
        return _decodeReport(
            _evaluatePacked(
                offChainData, onChainData, operation, _tokenPack(onChainData.tokenAResult, onChainData.tokenBResult)
            )
        );
    }

    /**
     * @notice Decodes a packed liquidity risk report.
     * @param packedReport Packed risk report value.
     * @return report Decoded liquidity risk report.
     */
    function decode(uint256 packedReport) external pure returns (LiquidityV2DecodedRiskReport memory report) {
        return _decodeReport(packedReport);
    }

    /**
     * @notice Packs the on-chain liquidity flags and token flags into compact counts and bitmasks.
     * @param onChainData Liquidity guard result used for packing.
     * @return packedFlags Packed on-chain liquidity flags.
     * @return packedTokenFlags Packed token-level flags.
     * @return criticalCount Total critical findings.
     * @return warningCount Total warning findings.
     * @return anyHardBlock True when any hard-block condition is present.
     * @return tokenCriticalCount Critical findings contributed by token analysis.
     * @return tokenWarningCount Warning findings contributed by token analysis.
     */
    function packOnChain(LiquidityV2GuardResult memory onChainData)
        external
        pure
        returns (
            uint32 packedFlags,
            uint32 packedTokenFlags,
            uint8 criticalCount,
            uint8 warningCount,
            bool anyHardBlock,
            uint8 tokenCriticalCount,
            uint8 tokenWarningCount
        )
    {
        PolicyOnChainPack memory packed = _packOnChain(
            onChainData, _tokenPack(onChainData.tokenAResult, onChainData.tokenBResult)
        );
        return (
            packed.flagsPacked,
            packed.tokenFlagsPacked,
            packed.criticalCount,
            packed.warningCount,
            packed.anyHardBlock,
            packed.tokenCriticalCount,
            packed.tokenWarningCount
        );
    }

    /**
     * @notice Decodes and normalizes liquidity off-chain simulation data.
     * @param offChainData ABI-encoded LiquidityOffChainResult from CRE simulation.
     * @return normalized Normalized off-chain findings.
     * @return economicData Extracted economic metrics from the off-chain result.
     */
    function decodeOffChain(bytes calldata offChainData)
        external
        pure
        returns (PolicyNormalizedOffChainResult memory normalized, ExtendedEconomicData memory economicData)
    {
        if (offChainData.length == 0) return (normalized, economicData);
        LiquidityOffChainResult memory offChainReport = abi.decode(offChainData, (LiquidityOffChainResult));
        normalized = _normalizeLiquidity(offChainReport);
        economicData = _extractLiquidityEconomic(offChainReport);
    }

    function _evaluatePacked(
        bytes calldata offChainData,
        LiquidityV2GuardResult memory onChainData,
        LiquidityOpType operation,
        PolicyTokenPack memory tokenPack
    ) internal pure returns (uint256 packedReport) {
        PolicyNormalizedOffChainResult memory offChain;
        ExtendedEconomicData memory economicData;

        if (offChainData.length > 0) {
            LiquidityOffChainResult memory offChainReport = abi.decode(offChainData, (LiquidityOffChainResult));
            offChain = _normalizeLiquidity(offChainReport);
            economicData = _extractLiquidityEconomic(offChainReport);
        }

        PolicyOnChainPack memory onChain = _packOnChain(onChainData, tokenPack);

        return _buildPackedPolicy(
            PolicyKind.LIQUIDITY_V2,
            uint8(operation),
            onChain.criticalCount,
            onChain.warningCount,
            onChain.anyHardBlock,
            onChain.flagsPacked,
            tokenPack,
            offChain,
            economicData
        );
    }

    function _decodeReport(uint256 packedReport) internal pure returns (LiquidityV2DecodedRiskReport memory report) {
        PolicyCoreView memory core;
        PolicyOffChainView memory offChain;
        PolicyTokenFlagsView memory tokenRisk;
        (core, offChain, tokenRisk) = _decodeBase(packedReport);
        _assertKind(core.kind, PolicyKind.LIQUIDITY_V2);

        report.core = core;
        report.offChain = offChain;
        report.tokenRisk = tokenRisk;
        report.operation = LiquidityOpType(core.operation);
        report.onChain = LiquidityV2OnChainView({
            routerNotTrusted: _isFlagSet(core.onChainFlagsPacked, FLAG_ROUTER_NOT_TRUSTED),
            pairNotExists: _isFlagSet(core.onChainFlagsPacked, FLAG_PAIR_NOT_EXISTS),
            zeroLiquidity: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_LIQUIDITY),
            lowLiquidity: _isFlagSet(core.onChainFlagsPacked, FLAG_LOW_LIQUIDITY),
            lowLpSupply: _isFlagSet(core.onChainFlagsPacked, FLAG_LOW_LP_SUPPLY),
            firstDepositorRisk: _isFlagSet(core.onChainFlagsPacked, FLAG_FIRST_DEPOSITOR_RISK),
            severeImbalance: _isFlagSet(core.onChainFlagsPacked, FLAG_SEVERE_IMBALANCE),
            kInvariantBroken: _isFlagSet(core.onChainFlagsPacked, FLAG_K_INVARIANT_BROKEN),
            poolTooNew: _isFlagSet(core.onChainFlagsPacked, FLAG_POOL_TOO_NEW),
            amountRatioDeviation: _isFlagSet(core.onChainFlagsPacked, FLAG_AMOUNT_RATIO_DEVIATION),
            highLpImpact: _isFlagSet(core.onChainFlagsPacked, FLAG_HIGH_LP_IMPACT),
            flashloanRisk: _isFlagSet(core.onChainFlagsPacked, FLAG_FLASHLOAN_RISK),
            zeroLpOut: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_LP_OUT),
            zeroAmountsOut: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_AMOUNTS_OUT),
            dustLp: _isFlagSet(core.onChainFlagsPacked, FLAG_DUST_LP)
        });
    }

    function _packOnChain(LiquidityV2GuardResult memory onChainData, PolicyTokenPack memory tokenPack)
        internal
        pure
        returns (PolicyOnChainPack memory packed)
    {
        if (onChainData.ROUTER_NOT_TRUSTED) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_ROUTER_NOT_TRUSTED;
        }
        if (onChainData.PAIR_NOT_EXISTS) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_PAIR_NOT_EXISTS;
            packed.anyHardBlock = true;
        }
        if (onChainData.ZERO_LIQUIDITY) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_ZERO_LIQUIDITY;
            packed.anyHardBlock = true;
        }
        if (onChainData.LOW_LIQUIDITY) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_LOW_LIQUIDITY;
        }
        if (onChainData.LOW_LP_SUPPLY) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_LOW_LP_SUPPLY;
        }
        if (onChainData.FIRST_DEPOSITOR_RISK) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_FIRST_DEPOSITOR_RISK;
            packed.anyHardBlock = true;
        }
        if (onChainData.SEVERE_IMBALANCE) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_SEVERE_IMBALANCE;
        }
        if (onChainData.K_INVARIANT_BROKEN) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_K_INVARIANT_BROKEN;
            packed.anyHardBlock = true;
        }
        if (onChainData.POOL_TOO_NEW) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_POOL_TOO_NEW;
        }
        if (onChainData.AMOUNT_RATIO_DEVIATION) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_AMOUNT_RATIO_DEVIATION;
        }
        if (onChainData.HIGH_LP_IMPACT) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_HIGH_LP_IMPACT;
        }
        if (onChainData.FLASHLOAN_RISK) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_FLASHLOAN_RISK;
        }
        if (onChainData.ZERO_LP_OUT) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_ZERO_LP_OUT;
            packed.anyHardBlock = true;
        }
        if (onChainData.ZERO_AMOUNTS_OUT) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_ZERO_AMOUNTS_OUT;
            packed.anyHardBlock = true;
        }
        if (onChainData.DUST_LP) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DUST_LP;
        }

        packed.tokenFlagsPacked = tokenPack.flagsPacked;
        packed.tokenCriticalCount = tokenPack.criticalCount;
        packed.tokenWarningCount = tokenPack.warningCount;
        packed.criticalCount += tokenPack.criticalCount;
        packed.warningCount += tokenPack.warningCount;
        packed.anyHardBlock = packed.anyHardBlock || tokenPack.anyHardBlock;
    }

    function _tokenPack(TokenGuardResult memory tokenAResult, TokenGuardResult memory tokenBResult)
        internal
        pure
        returns (PolicyTokenPack memory tokenPack)
    {
        uint32 flagsPacked = _packTokenFlags(tokenAResult) | _packTokenFlags(tokenBResult);
        tokenPack = _toTokenPack(flagsPacked, true);
    }

    function _normalizeLiquidity(LiquidityOffChainResult memory offChainReport)
        internal
        pure
        returns (PolicyNormalizedOffChainResult memory normalized)
    {
        normalized.valid = offChainReport.simulatedAt != 0;
        normalized.riskScore = _capRiskScore(offChainReport.riskScore);
        normalized.hasDangerousDelegateCall = offChainReport.trace.hasDangerousDelegateCall;
        normalized.hasSelfDestruct = offChainReport.trace.hasSelfDestruct;
        normalized.hasApprovalDrain = offChainReport.trace.hasApprovalDrain;
        normalized.hasOwnerSweep = offChainReport.trace.hasOwnerSweep;
        normalized.hasReentrancy = offChainReport.trace.hasReentrancy;
        normalized.hasUnexpectedCreate = offChainReport.trace.hasUnexpectedCreate;
        normalized.hasUpgradeCall = false;
        normalized.isExitFrozen = false;

        bool stealthRemovalHoneypot = !offChainReport.economic.isRemovalFrozen
            && offChainReport.economic.removalSimAmountA == 0 && offChainReport.economic.removalSimAmountB == 0
            && offChainReport.simulatedAt != 0;

        normalized.isRemovalFrozen = offChainReport.economic.isRemovalFrozen || stealthRemovalHoneypot;
        normalized.isFirstDeposit = offChainReport.economic.isFirstDeposit;
        normalized.isFeeOnTransfer = false;
        normalized.anyOracleStale =
            offChainReport.economic.tokenAOracleStale || offChainReport.economic.tokenBOracleStale;
        normalized.anyContractUnverified =
        !(offChainReport.routerVerified && offChainReport.pairVerified && offChainReport.tokenAVerified
                && offChainReport.tokenBVerified);
        normalized.oracleDeviation = offChainReport.economic.ratioDeviationBps > 500;
        normalized.simulationReverted = offChainReport.economic.simulationReverted;
        normalized.priceImpactBps = 0;
        normalized.outputDiscrepancyBps = _capUint16(offChainReport.economic.lpMintDiscrepancyBps);
        normalized.ratioDeviationBps = _capUint16(offChainReport.economic.ratioDeviationBps);
    }

    /**
     * @dev Extracts all rich numeric fields from LiquidityOffChainResult.
     */
    function _extractLiquidityEconomic(LiquidityOffChainResult memory offChainReport)
        internal
        pure
        returns (ExtendedEconomicData memory economicData)
    {
        economicData.lpMintDiscrepancyBps = offChainReport.economic.lpMintDiscrepancyBps;
        economicData.ratioDeviationBps = offChainReport.economic.ratioDeviationBps;
        economicData.tokenAOracleAge = offChainReport.economic.tokenAOracleAge;
        economicData.tokenBOracleAge = offChainReport.economic.tokenBOracleAge;
        economicData.removalSimAmountA = offChainReport.economic.removalSimAmountA;
        economicData.removalSimAmountB = offChainReport.economic.removalSimAmountB;
        economicData.simulationReverted = offChainReport.economic.simulationReverted;
        economicData.isRemovalFrozen = offChainReport.economic.isRemovalFrozen;

        // Stealth removal honeypot
        bool stealthHoneypot = !offChainReport.economic.isRemovalFrozen
            && offChainReport.economic.removalSimAmountA == 0 && offChainReport.economic.removalSimAmountB == 0
            && offChainReport.simulatedAt != 0;
        if (stealthHoneypot) economicData.isRemovalFrozen = true;

        // USD value of excess lost (combined A + B).
        economicData.excessValueLostUSD = offChainReport.economic.excessValueLostUSD;
        if (
            economicData.excessValueLostUSD == 0
                && (offChainReport.economic.excessTokenALost > 0 || offChainReport.economic.excessTokenBLost > 0)
        ) {
            uint256 lostA = offChainReport.economic.tokenAPriceUSD > 0
                ? (offChainReport.economic.excessTokenALost * offChainReport.economic.tokenAPriceUSD) / 1e18
                : 0;
            uint256 lostB = offChainReport.economic.tokenBPriceUSD > 0
                ? (offChainReport.economic.excessTokenBLost * offChainReport.economic.tokenBPriceUSD) / 1e18
                : 0;
            economicData.excessValueLostUSD = lostA + lostB;
        }

        // Owner sweep value
        economicData.sweepDetected = offChainReport.trace.hasOwnerSweep;
        if (economicData.sweepDetected && offChainReport.trace.sweepAmount > 0) {
            // Use tokenA price as approximation (sweep token may be either token)
            uint256 priceUSD = offChainReport.economic.tokenAPriceUSD > 0
                ? offChainReport.economic.tokenAPriceUSD
                : offChainReport.economic.tokenBPriceUSD;
            economicData.sweepAmountUSD = priceUSD > 0 ? (offChainReport.trace.sweepAmount * priceUSD) / 1e18 : 0;
        }
    }
}
