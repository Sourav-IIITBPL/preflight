// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRiskCategory,PolicyKind,PolicyNormalizedOffChainResult,PolicyCoreView,PolicyOffChainView,
PolicyOnChainPack , PolicyTokenPack, PolicyTokenFlagsView } from "../types/OnChainTypes.sol";
import {VaultOffChainResult, VaultOpType} from "../types/OffChainTypes.sol";
import {TokenGuardResult,VaultGuardResult} from "../types/OnChainTypes.sol";
import {BaseRiskPolicy} from "./BaseRiskPolicy.sol";

struct ERC4626OnChainView {
    bool vaultNotWhitelisted;
    bool vaultZeroSupply;
    bool donationAttack;
    bool shareInflationRisk;
    bool vaultBalanceMismatch;
    bool exchangeRateAnomaly;
    bool previewRevert;
    bool zeroSharesOut;
    bool zeroAssetsOut;
    bool dustShares;
    bool dustAssets;
    bool exceedsMaxDeposit;
    bool exceedsMaxRedeem;
    bool previewConvertMismatch;
}

struct ERC4626DecodedRiskReport {
    PolicyCoreView core;
    PolicyOffChainView offChain;
    PolicyTokenFlagsView tokenRisk;
    VaultOpType operation;
    ERC4626OnChainView onChain;
}

contract ERC4626RiskPolicy is BaseRiskPolicy {
    uint8 internal constant FLAG_VAULT_NOT_WHITELISTED = 0;
    uint8 internal constant FLAG_VAULT_ZERO_SUPPLY = 1;
    uint8 internal constant FLAG_DONATION_ATTACK = 2;
    uint8 internal constant FLAG_SHARE_INFLATION_RISK = 3;
    uint8 internal constant FLAG_VAULT_BALANCE_MISMATCH = 4;
    uint8 internal constant FLAG_EXCHANGE_RATE_ANOMALY = 5;
    uint8 internal constant FLAG_PREVIEW_REVERT = 6;
    uint8 internal constant FLAG_ZERO_SHARES_OUT = 7;
    uint8 internal constant FLAG_ZERO_ASSETS_OUT = 8;
    uint8 internal constant FLAG_DUST_SHARES = 9;
    uint8 internal constant FLAG_DUST_ASSETS = 10;
    uint8 internal constant FLAG_EXCEEDS_MAX_DEPOSIT = 11;
    uint8 internal constant FLAG_EXCEEDS_MAX_REDEEM = 12;
    uint8 internal constant FLAG_PREVIEW_CONVERT_MISMATCH = 13;

        function evaluate(
        bytes calldata offChainData,
        VaultGuardResult calldata onChainData,
        VaultOpType operation
    ) external pure returns (uint256 packedReport) {
        return _evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenResult));
    }


       function previewReport(
        bytes calldata offChainData,
        VaultGuardResult calldata onChainData,
        VaultOpType operation
    ) external pure returns (ERC4626DecodedRiskReport memory report) {
        return _decodeReport(_evaluatePacked(offChainData, onChainData, operation, _tokenPack(onChainData.tokenResult)));
    }

    function decode(uint256 packedReport) external pure returns (ERC4626DecodedRiskReport memory report) {
        return _decodeReport(packedReport);
    }

       function packOnChain(
        VaultGuardResult calldata onChainData,
        VaultOpType operation
    )
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
        PolicyOnChainPack memory packed = _packOnChain(onChainData, operation, _tokenPack(onChainData.tokenResult));
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
        VaultGuardResult calldata onChainData,
        VaultOpType operation,
        PolicyTokenPack memory tokenPack
    ) internal pure returns (uint256 packedReport) {
        PolicyOnChainPack memory onChain = _packOnChain(onChainData, operation, tokenPack);
        PolicyNormalizedOffChainResult memory offChain = _decodeOffChain(offChainData);

        packedReport = _buildPackedPolicy(
            PolicyKind.ERC4626,
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
        returns (ERC4626DecodedRiskReport memory report)
    {
        (PolicyCoreView memory core, PolicyOffChainView memory offChain, PolicyTokenFlagsView memory tokenRisk) =
            _decodeBase(packedReport);
        _assertKind(core.kind, PolicyKind.ERC4626);

        report.core = core;
        report.offChain = offChain;
        report.tokenRisk = tokenRisk;
        report.operation = VaultOpType(core.operation);
        report.onChain = ERC4626OnChainView({
            vaultNotWhitelisted: _isFlagSet(core.onChainFlagsPacked, FLAG_VAULT_NOT_WHITELISTED),
            vaultZeroSupply: _isFlagSet(core.onChainFlagsPacked, FLAG_VAULT_ZERO_SUPPLY),
            donationAttack: _isFlagSet(core.onChainFlagsPacked, FLAG_DONATION_ATTACK),
            shareInflationRisk: _isFlagSet(core.onChainFlagsPacked, FLAG_SHARE_INFLATION_RISK),
            vaultBalanceMismatch: _isFlagSet(core.onChainFlagsPacked, FLAG_VAULT_BALANCE_MISMATCH),
            exchangeRateAnomaly: _isFlagSet(core.onChainFlagsPacked, FLAG_EXCHANGE_RATE_ANOMALY),
            previewRevert: _isFlagSet(core.onChainFlagsPacked, FLAG_PREVIEW_REVERT),
            zeroSharesOut: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_SHARES_OUT),
            zeroAssetsOut: _isFlagSet(core.onChainFlagsPacked, FLAG_ZERO_ASSETS_OUT),
            dustShares: _isFlagSet(core.onChainFlagsPacked, FLAG_DUST_SHARES),
            dustAssets: _isFlagSet(core.onChainFlagsPacked, FLAG_DUST_ASSETS),
            exceedsMaxDeposit: _isFlagSet(core.onChainFlagsPacked, FLAG_EXCEEDS_MAX_DEPOSIT),
            exceedsMaxRedeem: _isFlagSet(core.onChainFlagsPacked, FLAG_EXCEEDS_MAX_REDEEM),
            previewConvertMismatch: _isFlagSet(core.onChainFlagsPacked, FLAG_PREVIEW_CONVERT_MISMATCH)
        });
    }

    function _packOnChain(
        VaultGuardResult calldata onChainData,
        VaultOpType operation,
        PolicyTokenPack memory tokenPack
    )
        internal
        pure
        returns (PolicyOnChainPack memory packed)
    {
        bool depositSide = operation == VaultOpType.DEPOSIT || operation == VaultOpType.MINT;

        if (onChainData.VAULT_NOT_WHITELISTED) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_VAULT_NOT_WHITELISTED;
        }
        if (onChainData.VAULT_ZERO_SUPPLY) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_VAULT_ZERO_SUPPLY;
        }
        if (onChainData.DONATION_ATTACK) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DONATION_ATTACK;
            packed.anyHardBlock = true;
        }
        if (onChainData.SHARE_INFLATION_RISK) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_SHARE_INFLATION_RISK;
        }
        if (onChainData.VAULT_BALANCE_MISMATCH) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_VAULT_BALANCE_MISMATCH;
            packed.anyHardBlock = true;
        }
        if (onChainData.EXCHANGE_RATE_ANOMALY) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_EXCHANGE_RATE_ANOMALY;
        }
        if (onChainData.PREVIEW_REVERT) {
            packed.criticalCount++;
            packed.flagsPacked |= uint32(1) << FLAG_PREVIEW_REVERT;
            packed.anyHardBlock = true;
        }
        if (onChainData.ZERO_SHARES_OUT) {
            packed.flagsPacked |= uint32(1) << FLAG_ZERO_SHARES_OUT;
            if (depositSide) {
                packed.criticalCount++;
                packed.anyHardBlock = true;
            } else {
                packed.warningCount++;
            }
        }
        if (onChainData.ZERO_ASSETS_OUT) {
            packed.flagsPacked |= uint32(1) << FLAG_ZERO_ASSETS_OUT;
            if (!depositSide) {
                packed.criticalCount++;
                packed.anyHardBlock = true;
            } else {
                packed.warningCount++;
            }
        }
        if (onChainData.DUST_SHARES) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DUST_SHARES;
        }
        if (onChainData.DUST_ASSETS) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_DUST_ASSETS;
        }
        if (onChainData.EXCEEDS_MAX_DEPOSIT) {
            packed.flagsPacked |= uint32(1) << FLAG_EXCEEDS_MAX_DEPOSIT;
            if (depositSide) {
                packed.criticalCount++;
                packed.anyHardBlock = true;
            } else {
                packed.warningCount++;
            }
        }
        if (onChainData.EXCEEDS_MAX_REDEEM) {
            packed.flagsPacked |= uint32(1) << FLAG_EXCEEDS_MAX_REDEEM;
            if (!depositSide) {
                packed.criticalCount++;
                packed.anyHardBlock = true;
            } else {
                packed.warningCount++;
            }
        }
        if (onChainData.PREVIEW_CONVERT_MISMATCH) {
            packed.warningCount++;
            packed.flagsPacked |= uint32(1) << FLAG_PREVIEW_CONVERT_MISMATCH;
        }

        packed.tokenFlagsPacked = tokenPack.flagsPacked;
        packed.tokenCriticalCount = tokenPack.criticalCount;
        packed.tokenWarningCount = tokenPack.warningCount;
        packed.criticalCount += tokenPack.criticalCount;
        packed.warningCount += tokenPack.warningCount;
        packed.anyHardBlock = packed.anyHardBlock || tokenPack.anyHardBlock;
    }

    function _tokenPack(TokenGuardResult memory tokenResult) internal pure returns (PolicyTokenPack memory tokenPack) {
        return _toTokenPack(_packTokenFlags(tokenResult), true);
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
        VaultOffChainResult memory offChainReport = abi.decode(raw, (VaultOffChainResult));
        normalized.valid = offChainReport.simulatedAt != 0;
        normalized.riskScore = _capRiskScore(offChainReport.riskScore);
        normalized.hasDangerousDelegateCall = offChainReport.trace.hasDangerousDelegateCall;
        normalized.hasSelfDestruct = offChainReport.trace.hasSelfDestruct;
        normalized.hasUnexpectedCreate = offChainReport.trace.hasUnexpectedCreate;
        normalized.hasApprovalDrain = offChainReport.trace.hasApprovalDrain;
        normalized.hasReentrancy = offChainReport.trace.hasReentrancy;
        normalized.hasOwnerSweep = offChainReport.trace.hasOwnerSweep;
        normalized.hasUpgradeCall = offChainReport.trace.hasUpgradeCall;
        normalized.isExitFrozen = offChainReport.economic.isExitFrozen;
        normalized.isRemovalFrozen = false;
        normalized.isFirstDeposit = false;
        normalized.isFeeOnTransfer = false;
        normalized.anyOracleStale = offChainReport.economic.assetOracleStale;
        normalized.anyContractUnverified = !(offChainReport.vaultVerified && offChainReport.assetVerified);
        normalized.oracleDeviation = offChainReport.economic.sharePriceDriftBps > 500;
        normalized.simulationReverted = offChainReport.economic.simulationReverted;
        normalized.priceImpactBps = 0;
        normalized.outputDiscrepancyBps = _capUint16(
            _max3(
                offChainReport.economic.outputDiscrepancyBps,
                offChainReport.economic.sharePriceDriftBps,
                offChainReport.economic.excessPullBps
            )
        );
        normalized.ratioDeviationBps = 0;
    }
}
