// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRiskCategory,PolicyKind,PolicyNormalizedOffChainResult,PolicyCoreView,PolicyOffChainView,
PolicyOnChainPack , PolicyTokenPack, PolicyTokenFlagsView } from "../types/OnChainTypes.sol";
import {LiquidityOffChainResult, LiquidityOpType} from "../types/OffChainTypes.sol";
import {TokenGuardResult,LiquidityV2GuardResult} from "../types/OnChainTypes.sol";
import {BaseRiskPolicy} from "./BaseRiskPolicy.sol";


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

struct LiquidityV2DecodedRiskReport {
    PolicyCoreView core;
    PolicyOffChainView offChain;
    PolicyTokenFlagsView tokenRisk;
    LiquidityOpType operation;
    LiquidityV2OnChainView onChain;
}

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

    function evaluate(
        bytes calldata offChainData,
        LiquidityV2GuardResult calldata onChainData,
        LiquidityOpType operation
    ) external pure returns (uint256 packedReport) {
        return _evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenAResult, onChainData.tokenBResult));
    }

      function previewReport(
        bytes calldata offChainData,
        LiquidityV2GuardResult calldata onChainData,
        LiquidityOpType operation
    ) external pure returns (LiquidityV2DecodedRiskReport memory report) {
        return _decodeReport(
            _evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenAResult, onChainData.tokenBResult))
        );
    }

    function decode(uint256 packedReport) external pure returns (LiquidityV2DecodedRiskReport memory report) {
        return _decodeReport(packedReport);
    }


    function packOnChain(
        LiquidityV2GuardResult calldata onChainData)
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
        PolicyOnChainPack memory packed = _packOnChain(onChainData, _tokenPack(onChainData.tokenAResult,onChainData.tokenBResult));
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
        returns (PolicyNormalizedOffChainResult memory normalized)
    {
        return _decodeOffChain(offChainData);
    }

    function _evaluatePacked(
        bytes calldata offChainData,
        LiquidityV2GuardResult calldata onChainData,
        LiquidityOpType operation,
        PolicyTokenPack memory tokenPack
    ) internal pure returns (uint256 packedReport) {
        PolicyOnChainPack memory onChain = _packOnChain(onChainData, tokenPack);
        PolicyNormalizedOffChainResult memory offChain = _decodeOffChain(offChainData);

        packedReport = _buildPackedPolicy(
            PolicyKind.LIQUIDITY_V2,
            uint8(operation),
            onChain.criticalCount,
            onChain.warningCount,
            onChain.anyHardBlock,
            onChain.flagsPacked,
            tokenPack,
            offChain
        );
    }

    function _decodeReport(uint256 packedReport)
        internal
        pure
        returns (LiquidityV2DecodedRiskReport memory report)
    {
        (PolicyCoreView memory core, PolicyOffChainView memory offChain, PolicyTokenFlagsView memory tokenRisk) =
            _decodeBase(packedReport);
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

    function _packOnChain(LiquidityV2GuardResult calldata onChainData, PolicyTokenPack memory tokenPack)
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

    function _decodeOffChain(bytes calldata offChainData)
        internal
        pure
        returns (PolicyNormalizedOffChainResult memory normalized)
    {
        if (offChainData.length == 0) {
            return normalized;
        }

        bytes memory raw = offChainData;
        LiquidityOffChainResult memory offChainReport = abi.decode(raw, (LiquidityOffChainResult));
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
        normalized.isRemovalFrozen = offChainReport.economic.isRemovalFrozen;
        normalized.isFirstDeposit = offChainReport.economic.isFirstDeposit;
        normalized.isFeeOnTransfer = false;
        normalized.anyOracleStale = offChainReport.economic.tokenAOracleStale || offChainReport.economic.tokenBOracleStale;
        normalized.anyContractUnverified =
            !(offChainReport.routerVerified && offChainReport.pairVerified && offChainReport.tokenAVerified && offChainReport.tokenBVerified);
        normalized.oracleDeviation = offChainReport.economic.ratioDeviationBps > 500;
        normalized.simulationReverted = offChainReport.economic.simulationReverted;
        normalized.priceImpactBps = 0;
        normalized.outputDiscrepancyBps = _capUint16(offChainReport.economic.lpMintDiscrepancyBps);
        normalized.ratioDeviationBps = _capUint16(offChainReport.economic.ratioDeviationBps);
    }
}
