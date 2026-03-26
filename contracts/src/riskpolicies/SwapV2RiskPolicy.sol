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
import {SwapOffChainResult, SwapOpType} from "../types/OffChainTypes.sol";
import {TokenGuardResult, SwapV2GuardResult} from "../types/OnChainTypes.sol";
import {BaseRiskPolicy, EnhancedCoreView} from "./BaseRiskPolicy.sol";

struct SwapV2OnChainView {
    bool routerNotTrusted;
    bool factoryNotTrusted;
    bool deepMultihop;
    bool duplicateTokenInPath;
    bool poolNotExists;
    bool factoryMismatch;
    bool zeroLiquidity;
    bool lowLiquidity;
    bool lowLpSupply;
    bool poolTooNew;
    bool severeImbalance;
    bool kInvariantBroken;
    bool highSwapImpact;
    bool flashloanRisk;
    bool priceManipulated;
}

struct SwapV2DecodedRiskReport {
    PolicyCoreView core;
    PolicyOffChainView offChain;
    PolicyTokenFlagsView tokenRisk;
    EnhancedCoreView enhancedView;
    SwapOpType operation;
    SwapV2OnChainView onChain;
}

contract SwapV2RiskPolicy is BaseRiskPolicy {
    uint8 internal constant FLAG_ROUTER_NOT_TRUSTED = 0;
    uint8 internal constant FLAG_FACTORY_NOT_TRUSTED = 1;
    uint8 internal constant FLAG_DEEP_MULTIHOP = 2;
    uint8 internal constant FLAG_DUPLICATE_TOKEN_IN_PATH = 3;
    uint8 internal constant FLAG_POOL_NOT_EXISTS = 4;
    uint8 internal constant FLAG_FACTORY_MISMATCH = 5;
    uint8 internal constant FLAG_ZERO_LIQUIDITY = 6;
    uint8 internal constant FLAG_LOW_LIQUIDITY = 7;
    uint8 internal constant FLAG_LOW_LP_SUPPLY = 8;
    uint8 internal constant FLAG_POOL_TOO_NEW = 9;
    uint8 internal constant FLAG_SEVERE_IMBALANCE = 10;
    uint8 internal constant FLAG_K_INVARIANT_BROKEN = 11;
    uint8 internal constant FLAG_HIGH_SWAP_IMPACT = 12;
    uint8 internal constant FLAG_FLASHLOAN_RISK = 13;
    uint8 internal constant FLAG_PRICE_MANIPULATED = 14;

    /**
     * @notice Full evaluation with token-level analysis.
     *
     * @param offChainData  ABI-encoded SwapOffChainResult from CRE simulation.
     * @param onChainData   SwapV2GuardRiskInput (guard check result without token arrays).
     * @param operation     SwapOpType enum value.
     */
    function evaluate(bytes calldata offChainData, SwapV2GuardResult calldata onChainData, SwapOpType operation)
        external
        pure
        returns (uint256 packedReport)
    {
        return _evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenResult));
    }

    function previewReport(bytes calldata offChainData, SwapV2GuardResult calldata onChainData, SwapOpType operation)
        external
        pure
        returns (SwapV2DecodedRiskReport memory report)
    {
        return _decodeReport(_evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenResult)));
    }

    function decode(uint256 packedReport) external pure returns (SwapV2DecodedRiskReport memory report) {
        return _decodeReport(packedReport);
    }

    function packOnChain(SwapV2GuardResult calldata onChainData)
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
        PolicyOnChainPack memory packed = _packOnChain(onChainData, _tokenPack(onChainData.tokenResult));
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

    function decodeOffChain(bytes calldata offChainData)
        external
        pure
        returns (PolicyNormalizedOffChainResult memory normalized, ExtendedEconomicData memory economicData)
    {
        if (offChainData.length == 0) return (normalized, economicData);
        SwapOffChainResult memory offChainResult = abi.decode(offChainData, (SwapOffChainResult));
        normalized = _normalizeSwap(offChainResult);
        economicData = _extractSwapEconomic(offChainResult);
    }

    function _evaluatePacked(
        bytes calldata offChainData,
        SwapV2GuardResult calldata onChainData,
        SwapOpType operation,
        PolicyTokenPack memory tokenPack
    ) internal pure returns (uint256 packedReport) {
        PolicyNormalizedOffChainResult memory offChain;
        ExtendedEconomicData memory economicData;

        if (offChainData.length > 0) {
            SwapOffChainResult memory offChainResult = abi.decode(offChainData, (SwapOffChainResult));
            offChain = _normalizeSwap(offChainResult);
            economicData = _extractSwapEconomic(offChainResult);
        }

        PolicyOnChainPack memory onChain = _packOnChain(onChainData, tokenPack);

        return _buildPackedPolicy(
            PolicyKind.SWAP_V2,
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

    function _decodeReport(uint256 packedReport) internal pure returns (SwapV2DecodedRiskReport memory report) {
        (PolicyCoreView memory core, PolicyOffChainView memory offChain, PolicyTokenFlagsView memory tokenRisk) =
            _decodeBase(packedReport);
        _assertKind(core.kind, PolicyKind.SWAP_V2);

        report.core = core;
        report.offChain = offChain;
        report.tokenRisk = tokenRisk;
        report.operation = SwapOpType(core.operation);
        report.onChain = SwapV2OnChainView({
            routerNotTrusted: _isFlagSet(core.onChainFlagsPacked, FLAG_ROUTER_NOT_TRUSTED),
            factoryNotTrusted: _isFlagSet(core.onChainFlagsPacked, FLAG_FACTORY_NOT_TRUSTED),
            deepMultihop: _isFlagSet(core.onChainFlagsPacked, FLAG_DEEP_MULTIHOP),
            duplicateTokenInPath: _isFlagSet(core.onChainFlagsPacked, FLAG_DUPLICATE_TOKEN_IN_PATH),
            poolNotExists: _isFlagSet(core.onChainFlagsPacked, FLAG_POOL_NOT_EXISTS),
            factoryMismatch: _isFlagSet(core.onChainFlagsPacked, FLAG_FACTORY_MISMATCH),
            zeroLiquidity: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_LIQUIDITY),
            lowLiquidity: _isFlagSet(core.onChainFlagsPacked, FLAG_LOW_LIQUIDITY),
            lowLpSupply: _isFlagSet(core.onChainFlagsPacked, FLAG_LOW_LP_SUPPLY),
            poolTooNew: _isFlagSet(core.onChainFlagsPacked, FLAG_POOL_TOO_NEW),
            severeImbalance: _isFlagSet(core.onChainFlagsPacked, FLAG_SEVERE_IMBALANCE),
            kInvariantBroken: _isFlagSet(core.onChainFlagsPacked, FLAG_K_INVARIANT_BROKEN),
            highSwapImpact: _isFlagSet(core.onChainFlagsPacked, FLAG_HIGH_SWAP_IMPACT),
            flashloanRisk: _isFlagSet(core.onChainFlagsPacked, FLAG_FLASHLOAN_RISK),
            priceManipulated: _isFlagSet(core.onChainFlagsPacked, FLAG_PRICE_MANIPULATED)
        });
    }

    function _packOnChain(SwapV2GuardResult calldata onChainData, PolicyTokenPack memory tokenPack)
        internal
        pure
        returns (PolicyOnChainPack memory packed)
    {
        if (onChainData.ROUTER_NOT_TRUSTED) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_ROUTER_NOT_TRUSTED;
        }
        if (onChainData.FACTORY_NOT_TRUSTED) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_FACTORY_NOT_TRUSTED;
        }
        if (onChainData.DEEP_MULTIHOP) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DEEP_MULTIHOP;
        }
        if (onChainData.DUPLICATE_TOKEN_IN_PATH) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DUPLICATE_TOKEN_IN_PATH;
            packed.anyHardBlock = true;
        }
        if (onChainData.POOL_NOT_EXISTS) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_POOL_NOT_EXISTS;
            packed.anyHardBlock = true;
        }
        if (onChainData.FACTORY_MISMATCH) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_FACTORY_MISMATCH;
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
        if (onChainData.POOL_TOO_NEW) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_POOL_TOO_NEW;
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
        if (onChainData.HIGH_SWAP_IMPACT) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_HIGH_SWAP_IMPACT;
        }
        if (onChainData.FLASHLOAN_RISK) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_FLASHLOAN_RISK;
        }
        if (onChainData.PRICE_MANIPULATED) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_PRICE_MANIPULATED;
            packed.anyHardBlock = true;
        }

        packed.tokenFlagsPacked = tokenPack.flagsPacked;
        packed.tokenCriticalCount = tokenPack.criticalCount;
        packed.tokenWarningCount = tokenPack.warningCount;
        packed.criticalCount += tokenPack.criticalCount;
        packed.warningCount += tokenPack.warningCount;
        packed.anyHardBlock = packed.anyHardBlock || tokenPack.anyHardBlock;
    }

    function _tokenPack(TokenGuardResult[] memory tokenResults)
        internal
        pure
        returns (PolicyTokenPack memory tokenPack)
    {
        uint32 flagsPacked;
        uint256 len = tokenResults.length;
        for (uint256 i = 0; i < len; ++i) {
            flagsPacked |= _packTokenFlags(tokenResults[i]);
        }
        tokenPack = _toTokenPack(flagsPacked, len != 0);
    }

    function _normalizeSwap(SwapOffChainResult memory offChainReport)
        internal
        pure
        returns (PolicyNormalizedOffChainResult memory normalized)
    {
        normalized.valid = offChainReport.simulatedAt != 0;
        normalized.riskScore = _capRiskScore(offChainReport.riskScore);
        normalized.hasDangerousDelegateCall = offChainReport.trace.hasDangerousDelegateCall;
        normalized.hasSelfDestruct = offChainReport.trace.hasSelfDestruct;
        normalized.hasApprovalDrain = offChainReport.trace.hasApprovalDrain;
        normalized.hasOwnerSweep = false;
        normalized.hasReentrancy = offChainReport.trace.hasReentrancy;
        normalized.hasUnexpectedCreate = offChainReport.trace.hasUnexpectedCreate;
        normalized.hasUpgradeCall = false;
        normalized.isExitFrozen = false;
        normalized.isRemovalFrozen = false;
        normalized.isFirstDeposit = false;
        normalized.isFeeOnTransfer = offChainReport.economic.isFeeOnTransfer;
        normalized.anyOracleStale =
            offChainReport.economic.tokenInOracleStale || offChainReport.economic.tokenOutOracleStale;
        normalized.anyContractUnverified =
        !(offChainReport.routerVerified && offChainReport.tokenInVerified && offChainReport.tokenOutVerified);
        normalized.oracleDeviation = offChainReport.economic.oracleDeviation;
        normalized.simulationReverted = offChainReport.economic.simulationReverted;
        normalized.priceImpactBps = _capUint16(offChainReport.economic.priceImpactBps);
        normalized.outputDiscrepancyBps = 0;
        normalized.ratioDeviationBps = 0;
    }

    /**
     * @dev Extracts rich numeric economic data from SwapOffChainResult.
     */
    function _extractSwapEconomic(SwapOffChainResult memory offChainReport)
        internal
        pure
        returns (ExtendedEconomicData memory economicData)
    {
        economicData.priceImpactBps = offChainReport.economic.priceImpactBps;
        economicData.measuredFeePercent = offChainReport.economic.measuredFeePercent;
        economicData.inputHeadroomBps = offChainReport.economic.inputHeadroomBps;
        economicData.tokenInOracleAge = offChainReport.economic.tokenInOracleAge;
        economicData.tokenOutOracleAge = offChainReport.economic.tokenOutOracleAge;
        economicData.oracleFairAmountOut = offChainReport.economic.oracleFairAmountOut;
        economicData.actualAmountOut = offChainReport.economic.actualAmountOut;
        economicData.simulationReverted = offChainReport.economic.simulationReverted;
        economicData.feeOnTransferConfirmed = offChainReport.economic.isFeeOnTransfer;

        // Derive our own oracle deviation % from raw amounts.
        // Deviation = |fair - actual| / fair × 10000 in bps.
        if (economicData.oracleFairAmountOut > 0 && economicData.actualAmountOut > 0) {
            uint256 fair = economicData.oracleFairAmountOut;
            uint256 actual = economicData.actualAmountOut;
            uint256 delta = fair > actual ? fair - actual : actual - fair;
            economicData.priceImpactBps = (delta * 10_000) / fair; // override with computed value
        }
    }
}
