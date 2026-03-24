// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenGuardResult} from "../types/OnChainTypes.sol";
import {PolicyRiskCategory,PolicyKind,PolicyNormalizedOffChainResult,PolicyCoreView,PolicyOffChainView,
PolicyOnChainPack , PolicyTokenPack, PolicyTokenFlagsView } from "../types/OnChainTypes.sol";

abstract contract BaseRiskPolicy {
    
    error InvalidPackedKind(uint8 expectedKind, uint8 actualKind);

    struct PolicyComputation {
        PolicyRiskCategory finalCategory;
        PolicyRiskCategory offChainCategory;
        uint8 compositeScore;
        uint8 onChainScore;
        uint8 offChainScore;
        uint8 offChainInfoCount;
        uint32 offChainFlagsPacked;
    }

    uint8 internal constant POLICY_VERSION = 1;

    uint8 internal constant W_HARD_BLOCK = 20;
    uint8 internal constant W_SOFT_FLAG = 10;
    uint8 internal constant W_OFFCHAIN_BASE_MAX = 30;
    uint8 internal constant W_TRACE = 25;
    uint8 internal constant W_HONEYPOT = 35;
    uint8 internal constant W_FIRST_DEPOSIT = 20;
    uint8 internal constant W_PRICE_IMPACT = 15;
    uint8 internal constant W_ORACLE_STALE = 5;
    uint8 internal constant W_UNVERIFIED = 5;

    uint8 internal constant THRESHOLD_CRITICAL = 70;
    uint8 internal constant THRESHOLD_MEDIUM = 40;
    uint8 internal constant THRESHOLD_WARNING = 20;

    uint8 internal constant OFFCHAIN_VALID = 0;
    uint8 internal constant OFFCHAIN_DANGEROUS_DELEGATECALL = 1;
    uint8 internal constant OFFCHAIN_SELFDESTRUCT = 2;
    uint8 internal constant OFFCHAIN_APPROVAL_DRAIN = 3;
    uint8 internal constant OFFCHAIN_OWNER_SWEEP = 4;
    uint8 internal constant OFFCHAIN_REENTRANCY = 5;
    uint8 internal constant OFFCHAIN_UNEXPECTED_CREATE = 6;
    uint8 internal constant OFFCHAIN_UPGRADE_CALL = 7;
    uint8 internal constant OFFCHAIN_EXIT_FROZEN = 8;
    uint8 internal constant OFFCHAIN_REMOVAL_FROZEN = 9;
    uint8 internal constant OFFCHAIN_FIRST_DEPOSIT = 10;
    uint8 internal constant OFFCHAIN_PRICE_IMPACT_HIGH = 11;
    uint8 internal constant OFFCHAIN_OUTPUT_DISCREPANCY_HIGH = 12;
    uint8 internal constant OFFCHAIN_RATIO_DEVIATION_HIGH = 13;
    uint8 internal constant OFFCHAIN_SIMULATION_REVERTED = 14;
    uint8 internal constant OFFCHAIN_FEE_ON_TRANSFER = 15;
    uint8 internal constant OFFCHAIN_ORACLE_STALE = 16;
    uint8 internal constant OFFCHAIN_CONTRACT_UNVERIFIED = 17;
    uint8 internal constant OFFCHAIN_ORACLE_DEVIATION = 18;

    uint8 internal constant TOKEN_NOT_A_CONTRACT = 0;
    uint8 internal constant TOKEN_EMPTY_BYTECODE = 1;
    uint8 internal constant TOKEN_DECIMALS_REVERT = 2;
    uint8 internal constant TOKEN_WEIRD_DECIMALS = 3;
    uint8 internal constant TOKEN_HIGH_DECIMALS = 4;
    uint8 internal constant TOKEN_TOTAL_SUPPLY_REVERT = 5;
    uint8 internal constant TOKEN_ZERO_TOTAL_SUPPLY = 6;
    uint8 internal constant TOKEN_VERY_LOW_TOTAL_SUPPLY = 7;
    uint8 internal constant TOKEN_SYMBOL_REVERT = 8;
    uint8 internal constant TOKEN_NAME_REVERT = 9;
    uint8 internal constant TOKEN_IS_EIP1967_PROXY = 10;
    uint8 internal constant TOKEN_IS_EIP1822_PROXY = 11;
    uint8 internal constant TOKEN_IS_MINIMAL_PROXY = 12;
    uint8 internal constant TOKEN_HAS_OWNER = 13;
    uint8 internal constant TOKEN_OWNERSHIP_RENOUNCED = 14;
    uint8 internal constant TOKEN_OWNER_IS_EOA = 15;
    uint8 internal constant TOKEN_IS_PAUSABLE = 16;
    uint8 internal constant TOKEN_IS_CURRENTLY_PAUSED = 17;
    uint8 internal constant TOKEN_HAS_BLACKLIST = 18;
    uint8 internal constant TOKEN_HAS_BLOCKLIST = 19;
    uint8 internal constant TOKEN_POSSIBLE_FEE_ON_TRANSFER = 20;
    uint8 internal constant TOKEN_HAS_TRANSFER_FEE_GETTER = 21;
    uint8 internal constant TOKEN_HAS_TAX_FUNCTION = 22;
    uint8 internal constant TOKEN_POSSIBLE_REBASING = 23;
    uint8 internal constant TOKEN_HAS_MINT_CAPABILITY = 24;
    uint8 internal constant TOKEN_HAS_BURN_CAPABILITY = 25;
    uint8 internal constant TOKEN_HAS_PERMIT = 26;
    uint8 internal constant TOKEN_HAS_FLASH_MINT = 27;


    uint8 internal constant SHIFT_ONCHAIN_FLAGS        = 0;
uint8 internal constant SHIFT_OFFCHAIN_FLAGS       = 32;
uint8 internal constant SHIFT_COMPOSITE_SCORE      = 64;
uint8 internal constant SHIFT_ONCHAIN_SCORE        = 72;
uint8 internal constant SHIFT_OFFCHAIN_SCORE       = 80;
uint8 internal constant SHIFT_FINAL_CATEGORY       = 88;
uint8 internal constant SHIFT_OFFCHAIN_CATEGORY    = 90;
uint8 internal constant SHIFT_ANY_HARD_BLOCK       = 92;
uint8 internal constant SHIFT_OFFCHAIN_VALID       = 93;
uint8 internal constant SHIFT_ONCHAIN_CRITICAL     = 94;
uint8 internal constant SHIFT_ONCHAIN_WARNING      = 100;
uint8 internal constant SHIFT_OFFCHAIN_INFO        = 106;
uint8 internal constant SHIFT_PRICE_IMPACT         = 112;
uint8 internal constant SHIFT_OUTPUT_DISCREPANCY   = 128;
uint8 internal constant SHIFT_RATIO_DEVIATION      = 144;
uint8 internal constant SHIFT_OPERATION            = 160;
uint8 internal constant SHIFT_POLICY_KIND          = 164;
uint8 internal constant SHIFT_POLICY_VERSION       = 166;
uint8 internal constant SHIFT_TOKEN_FLAGS          = 174;
uint8 internal constant SHIFT_TOKEN_CRITICAL       = 206;
uint8 internal constant SHIFT_TOKEN_WARNING        = 212;
uint8 internal constant SHIFT_TOKEN_EVALUATED      = 218;

    function _buildPackedPolicy(
        PolicyKind kind,
        uint8 operation,
        uint8 onChainCriticalCount,
        uint8 onChainWarningCount,
        bool anyHardBlock,
        uint32 onChainFlagsPacked,
        PolicyTokenPack memory tokenPack,
        PolicyNormalizedOffChainResult memory offChain
    ) internal pure returns (uint256 packedReport) {
        PolicyComputation memory policy =
            _computePolicy(onChainCriticalCount, onChainWarningCount, anyHardBlock, offChain);

        packedReport = uint256(onChainFlagsPacked);
        packedReport |= uint256(policy.offChainFlagsPacked) << SHIFT_OFFCHAIN_FLAGS;
        packedReport |= uint256(policy.compositeScore) << SHIFT_COMPOSITE_SCORE;
        packedReport |= uint256(policy.onChainScore) << SHIFT_ONCHAIN_SCORE;
        packedReport |= uint256(policy.offChainScore) << SHIFT_OFFCHAIN_SCORE;
        packedReport |= uint256(uint8(policy.finalCategory)) << SHIFT_FINAL_CATEGORY;
        packedReport |= uint256(uint8(policy.offChainCategory)) << SHIFT_OFFCHAIN_CATEGORY;
        packedReport |= uint256(_cap6(onChainCriticalCount)) << SHIFT_ONCHAIN_CRITICAL;
        packedReport |= uint256(_cap6(onChainWarningCount)) << SHIFT_ONCHAIN_WARNING;
        packedReport |= uint256(_cap6(policy.offChainInfoCount)) << SHIFT_OFFCHAIN_INFO;
        packedReport |= uint256(offChain.priceImpactBps) << SHIFT_PRICE_IMPACT;
        packedReport |= uint256(offChain.outputDiscrepancyBps) << SHIFT_OUTPUT_DISCREPANCY;
        packedReport |= uint256(offChain.ratioDeviationBps) << SHIFT_RATIO_DEVIATION;
        packedReport |= uint256(operation) << SHIFT_OPERATION;
        packedReport |= uint256(uint8(kind)) << SHIFT_POLICY_KIND;
        packedReport |= uint256(POLICY_VERSION) << SHIFT_POLICY_VERSION;
        packedReport |= uint256(tokenPack.flagsPacked) << SHIFT_TOKEN_FLAGS;
        packedReport |= uint256(_cap6(tokenPack.criticalCount)) << SHIFT_TOKEN_CRITICAL;
        packedReport |= uint256(_cap6(tokenPack.warningCount)) << SHIFT_TOKEN_WARNING;

        if (anyHardBlock) {
            packedReport |= uint256(1) << SHIFT_ANY_HARD_BLOCK;
        }
        if (offChain.valid) {
            packedReport |= uint256(1) << SHIFT_OFFCHAIN_VALID;
        }
        if (tokenPack.evaluated) {
            packedReport |= uint256(1) << SHIFT_TOKEN_EVALUATED;
        }
    }

    function _computePolicy(
        uint8 onChainCriticalCount,
        uint8 onChainWarningCount,
        bool anyHardBlock,
        PolicyNormalizedOffChainResult memory offChain
    ) internal pure returns (PolicyComputation memory policy) {
        uint32 offChainFlagsPacked = _packOffChainFlags(offChain);
        uint8 offChainInfoCount = _countSetBits32(_clearBit(offChainFlagsPacked, OFFCHAIN_VALID));

        bool traceAnomaly = offChain.valid
            && (
                offChain.hasDangerousDelegateCall
                    || offChain.hasSelfDestruct
                    || offChain.hasApprovalDrain
                    || offChain.hasOwnerSweep
                    || offChain.hasReentrancy
                    || offChain.hasUnexpectedCreate
                    || offChain.hasUpgradeCall
            );
        bool honeypot = offChain.valid && (offChain.isExitFrozen || offChain.isRemovalFrozen);
        bool priceImpactAnomaly = offChain.valid && (offChain.priceImpactBps > 500 || offChain.oracleDeviation);

        uint256 onChainScore = uint256(onChainCriticalCount) * W_HARD_BLOCK;
        onChainScore += uint256(onChainWarningCount) * W_SOFT_FLAG;
        onChainScore = _cap100(onChainScore);

        uint256 compositeScore = onChainScore;
        if (offChain.valid) {
            compositeScore = _cap100(compositeScore + ((uint256(offChain.riskScore) * W_OFFCHAIN_BASE_MAX) / 100));
        }
        if (traceAnomaly) {
            compositeScore = _addCapped(compositeScore, W_TRACE);
        }
        if (honeypot) {
            compositeScore = _addCapped(compositeScore, W_HONEYPOT);
        }
        if (offChain.valid && offChain.isFirstDeposit) {
            compositeScore = _addCapped(compositeScore, W_FIRST_DEPOSIT);
        }
        if (priceImpactAnomaly) {
            compositeScore = _addCapped(compositeScore, W_PRICE_IMPACT);
        }
        if (offChain.valid && offChain.anyOracleStale) {
            compositeScore = _addCapped(compositeScore, W_ORACLE_STALE);
        }
        if (offChain.valid && offChain.anyContractUnverified) {
            compositeScore = _addCapped(compositeScore, W_UNVERIFIED);
        }
        if (anyHardBlock) {
            compositeScore = _addCapped(compositeScore, W_HARD_BLOCK);
        }

        policy.finalCategory = _toRiskCategory(
            _toUint8(compositeScore),
            anyHardBlock || traceAnomaly || honeypot
        );
        policy.offChainCategory = offChain.valid ? _toRiskCategory(offChain.riskScore, false) : PolicyRiskCategory.INFO;
        policy.compositeScore = _toUint8(compositeScore);
        policy.onChainScore = _toUint8(onChainScore);
        policy.offChainScore = offChain.valid ? offChain.riskScore : 0;
        policy.offChainInfoCount = offChainInfoCount;
        policy.offChainFlagsPacked = offChainFlagsPacked;
    }

    function _decodeBase(uint256 packedReport)
        internal
        pure
        returns (PolicyCoreView memory core, PolicyOffChainView memory offChain, PolicyTokenFlagsView memory token)
    {
       core.kind = PolicyKind(_extract(packedReport, SHIFT_POLICY_KIND, 2));
core.operation = uint8(_extract(packedReport, SHIFT_OPERATION, 4));
core.version = uint8(_extract(packedReport, SHIFT_POLICY_VERSION, 8));
core.finalCategory = PolicyRiskCategory(_extract(packedReport, SHIFT_FINAL_CATEGORY, 2));
core.offChainCategory = PolicyRiskCategory(_extract(packedReport, SHIFT_OFFCHAIN_CATEGORY, 2));
core.compositeScore = uint8(_extract(packedReport, SHIFT_COMPOSITE_SCORE, 8));
core.onChainScore = uint8(_extract(packedReport, SHIFT_ONCHAIN_SCORE, 8));
core.offChainScore = uint8(_extract(packedReport, SHIFT_OFFCHAIN_SCORE, 8));
core.onChainCriticalCount = uint8(_extract(packedReport, SHIFT_ONCHAIN_CRITICAL, 6));
core.onChainWarningCount = uint8(_extract(packedReport, SHIFT_ONCHAIN_WARNING, 6));
core.offChainInfoCount = uint8(_extract(packedReport, SHIFT_OFFCHAIN_INFO, 6));
core.anyHardBlock = _extract(packedReport, SHIFT_ANY_HARD_BLOCK, 1) == 1;
core.offChainValid = _extract(packedReport, SHIFT_OFFCHAIN_VALID, 1) == 1;
core.onChainFlagsPacked = uint32(_extract(packedReport, SHIFT_ONCHAIN_FLAGS, 32));
core.offChainFlagsPacked = uint32(_extract(packedReport, SHIFT_OFFCHAIN_FLAGS, 32));
core.tokenFlagsPacked = uint32(_extract(packedReport, SHIFT_TOKEN_FLAGS, 32));
core.priceImpactBps = uint16(_extract(packedReport, SHIFT_PRICE_IMPACT, 16));
core.outputDiscrepancyBps = uint16(_extract(packedReport, SHIFT_OUTPUT_DISCREPANCY, 16));
core.ratioDeviationBps = uint16(_extract(packedReport, SHIFT_RATIO_DEVIATION, 16));
core.tokenCriticalCount = uint8(_extract(packedReport, SHIFT_TOKEN_CRITICAL, 6));
core.tokenWarningCount = uint8(_extract(packedReport, SHIFT_TOKEN_WARNING, 6));
core.tokenRiskEvaluated = _extract(packedReport, SHIFT_TOKEN_EVALUATED, 1) == 1;

        offChain.hasDangerousDelegateCall = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_DANGEROUS_DELEGATECALL);
        offChain.hasSelfDestruct = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_SELFDESTRUCT);
        offChain.hasApprovalDrain = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_APPROVAL_DRAIN);
        offChain.hasOwnerSweep = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_OWNER_SWEEP);
        offChain.hasReentrancy = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_REENTRANCY);
        offChain.hasUnexpectedCreate = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_UNEXPECTED_CREATE);
        offChain.hasUpgradeCall = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_UPGRADE_CALL);
        offChain.isExitFrozen = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_EXIT_FROZEN);
        offChain.isRemovalFrozen = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_REMOVAL_FROZEN);
        offChain.isFirstDeposit = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_FIRST_DEPOSIT);
        offChain.isFeeOnTransfer = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_FEE_ON_TRANSFER);
        offChain.anyOracleStale = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_ORACLE_STALE);
        offChain.anyContractUnverified = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_CONTRACT_UNVERIFIED);
        offChain.oracleDeviation = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_ORACLE_DEVIATION);
        offChain.simulationReverted = _isFlagSet(core.offChainFlagsPacked, OFFCHAIN_SIMULATION_REVERTED);

        token = _decodeTokenFlags(core.tokenFlagsPacked, core.tokenRiskEvaluated);
    }

    function _assertKind(PolicyKind actualKind, PolicyKind expectedKind) internal pure {
        if (actualKind != expectedKind) {
            revert InvalidPackedKind(uint8(expectedKind), uint8(actualKind));
        }
    }

    function _packOffChainFlags(PolicyNormalizedOffChainResult memory offChain)
        internal
        pure
        returns (uint32 flagsPacked)
    {
        if (offChain.valid) {
            flagsPacked |= uint32(1) << OFFCHAIN_VALID;
        }
        if (offChain.hasDangerousDelegateCall) {
            flagsPacked |= uint32(1) << OFFCHAIN_DANGEROUS_DELEGATECALL;
        }
        if (offChain.hasSelfDestruct) {
            flagsPacked |= uint32(1) << OFFCHAIN_SELFDESTRUCT;
        }
        if (offChain.hasApprovalDrain) {
            flagsPacked |= uint32(1) << OFFCHAIN_APPROVAL_DRAIN;
        }
        if (offChain.hasOwnerSweep) {
            flagsPacked |= uint32(1) << OFFCHAIN_OWNER_SWEEP;
        }
        if (offChain.hasReentrancy) {
            flagsPacked |= uint32(1) << OFFCHAIN_REENTRANCY;
        }
        if (offChain.hasUnexpectedCreate) {
            flagsPacked |= uint32(1) << OFFCHAIN_UNEXPECTED_CREATE;
        }
        if (offChain.hasUpgradeCall) {
            flagsPacked |= uint32(1) << OFFCHAIN_UPGRADE_CALL;
        }
        if (offChain.isExitFrozen) {
            flagsPacked |= uint32(1) << OFFCHAIN_EXIT_FROZEN;
        }
        if (offChain.isRemovalFrozen) {
            flagsPacked |= uint32(1) << OFFCHAIN_REMOVAL_FROZEN;
        }
        if (offChain.isFirstDeposit) {
            flagsPacked |= uint32(1) << OFFCHAIN_FIRST_DEPOSIT;
        }
        if (offChain.priceImpactBps > 500) {
            flagsPacked |= uint32(1) << OFFCHAIN_PRICE_IMPACT_HIGH;
        }
        if (offChain.outputDiscrepancyBps > 200) {
            flagsPacked |= uint32(1) << OFFCHAIN_OUTPUT_DISCREPANCY_HIGH;
        }
        if (offChain.ratioDeviationBps > 500) {
            flagsPacked |= uint32(1) << OFFCHAIN_RATIO_DEVIATION_HIGH;
        }
        if (offChain.simulationReverted) {
            flagsPacked |= uint32(1) << OFFCHAIN_SIMULATION_REVERTED;
        }
        if (offChain.isFeeOnTransfer) {
            flagsPacked |= uint32(1) << OFFCHAIN_FEE_ON_TRANSFER;
        }
        if (offChain.anyOracleStale) {
            flagsPacked |= uint32(1) << OFFCHAIN_ORACLE_STALE;
        }
        if (offChain.anyContractUnverified) {
            flagsPacked |= uint32(1) << OFFCHAIN_CONTRACT_UNVERIFIED;
        }
        if (offChain.oracleDeviation) {
            flagsPacked |= uint32(1) << OFFCHAIN_ORACLE_DEVIATION;
        }

    }

    function _toRiskCategory(uint8 score, bool forceCritical)
        internal
        pure
        returns (PolicyRiskCategory)
    {
        if (forceCritical || score >= THRESHOLD_CRITICAL) {
            return PolicyRiskCategory.CRITICAL;
        }
        if (score >= THRESHOLD_MEDIUM) {
            return PolicyRiskCategory.MEDIUM;
        }
        if (score >= THRESHOLD_WARNING) {
            return PolicyRiskCategory.WARNING;
        }
        return PolicyRiskCategory.INFO;
    }

    function _extract(uint256 packedReport, uint8 shift, uint8 width) internal pure returns (uint256) {
        return (packedReport >> shift) & ((uint256(1) << width) - 1);         
    }

    function _isFlagSet(uint32 packedFlags, uint8 bit) internal pure returns (bool) {
        return ((packedFlags >> bit) & uint32(1)) == 1;
    }

    function _countSetBits32(uint32 value) internal pure returns (uint8 count) {
        while (value != 0) {
            if ((value & 1) == 1) {
                count++;
            }
            value >>= 1;
        }
    }

    function _clearBit(uint32 value, uint8 bit) internal pure returns (uint32) {
        return value & ~(uint32(1) << bit);
    }

    function _cap100(uint256 value) internal pure returns (uint256) {
        return value > 100 ? 100 : value;
    }

    function _addCapped(uint256 baseValue, uint8 addend) internal pure returns (uint256) {
        return _cap100(baseValue + addend);
    }

    function _toUint8(uint256 value) internal pure returns (uint8) {
        return uint8(value > type(uint8).max ? type(uint8).max : value);
    }

    function _capRiskScore(uint256 value) internal pure returns (uint8) {
        return uint8(value > 100 ? 100 : value);
    }

    function _capUint16(uint256 value) internal pure returns (uint16) {
        return uint16(value > type(uint16).max ? type(uint16).max : value);
    }

    function _max3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 maxValue = a > b ? a : b;
        return maxValue > c ? maxValue : c;
    }

    function _cap6(uint8 value) internal pure returns (uint8) {
        return value > 63 ? 63 : value;
    }

    function _packTokenFlags(TokenGuardResult memory tokenResult) internal pure returns (uint32 flagsPacked) {
        if (tokenResult.NOT_A_CONTRACT) flagsPacked |= uint32(1) << TOKEN_NOT_A_CONTRACT;
        if (tokenResult.EMPTY_BYTECODE) flagsPacked |= uint32(1) << TOKEN_EMPTY_BYTECODE;
        if (tokenResult.DECIMALS_REVERT) flagsPacked |= uint32(1) << TOKEN_DECIMALS_REVERT;
        if (tokenResult.WEIRD_DECIMALS) flagsPacked |= uint32(1) << TOKEN_WEIRD_DECIMALS;
        if (tokenResult.HIGH_DECIMALS) flagsPacked |= uint32(1) << TOKEN_HIGH_DECIMALS;
        if (tokenResult.TOTAL_SUPPLY_REVERT) flagsPacked |= uint32(1) << TOKEN_TOTAL_SUPPLY_REVERT;
        if (tokenResult.ZERO_TOTAL_SUPPLY) flagsPacked |= uint32(1) << TOKEN_ZERO_TOTAL_SUPPLY;
        if (tokenResult.VERY_LOW_TOTAL_SUPPLY) flagsPacked |= uint32(1) << TOKEN_VERY_LOW_TOTAL_SUPPLY;
        if (tokenResult.SYMBOL_REVERT) flagsPacked |= uint32(1) << TOKEN_SYMBOL_REVERT;
        if (tokenResult.NAME_REVERT) flagsPacked |= uint32(1) << TOKEN_NAME_REVERT;
        if (tokenResult.IS_EIP1967_PROXY) flagsPacked |= uint32(1) << TOKEN_IS_EIP1967_PROXY;
        if (tokenResult.IS_EIP1822_PROXY) flagsPacked |= uint32(1) << TOKEN_IS_EIP1822_PROXY;
        if (tokenResult.IS_MINIMAL_PROXY) flagsPacked |= uint32(1) << TOKEN_IS_MINIMAL_PROXY;
        if (tokenResult.HAS_OWNER) flagsPacked |= uint32(1) << TOKEN_HAS_OWNER;
        if (tokenResult.OWNERSHIP_RENOUNCED) flagsPacked |= uint32(1) << TOKEN_OWNERSHIP_RENOUNCED;
        if (tokenResult.OWNER_IS_EOA) flagsPacked |= uint32(1) << TOKEN_OWNER_IS_EOA;
        if (tokenResult.IS_PAUSABLE) flagsPacked |= uint32(1) << TOKEN_IS_PAUSABLE;
        if (tokenResult.IS_CURRENTLY_PAUSED) flagsPacked |= uint32(1) << TOKEN_IS_CURRENTLY_PAUSED;
        if (tokenResult.HAS_BLACKLIST) flagsPacked |= uint32(1) << TOKEN_HAS_BLACKLIST;
        if (tokenResult.HAS_BLOCKLIST) flagsPacked |= uint32(1) << TOKEN_HAS_BLOCKLIST;
        if (tokenResult.POSSIBLE_FEE_ON_TRANSFER) flagsPacked |= uint32(1) << TOKEN_POSSIBLE_FEE_ON_TRANSFER;
        if (tokenResult.HAS_TRANSFER_FEE_GETTER) flagsPacked |= uint32(1) << TOKEN_HAS_TRANSFER_FEE_GETTER;
        if (tokenResult.HAS_TAX_FUNCTION) flagsPacked |= uint32(1) << TOKEN_HAS_TAX_FUNCTION;
        if (tokenResult.POSSIBLE_REBASING) flagsPacked |= uint32(1) << TOKEN_POSSIBLE_REBASING;
        if (tokenResult.HAS_MINT_CAPABILITY) flagsPacked |= uint32(1) << TOKEN_HAS_MINT_CAPABILITY;
        if (tokenResult.HAS_BURN_CAPABILITY) flagsPacked |= uint32(1) << TOKEN_HAS_BURN_CAPABILITY;
        if (tokenResult.HAS_PERMIT) flagsPacked |= uint32(1) << TOKEN_HAS_PERMIT;
        if (tokenResult.HAS_FLASH_MINT) flagsPacked |= uint32(1) << TOKEN_HAS_FLASH_MINT;
    }

    function _toTokenPack(uint32 flagsPacked, bool evaluated) internal pure returns (PolicyTokenPack memory tokenPack) {
        tokenPack.flagsPacked = flagsPacked;
        tokenPack.evaluated = evaluated;

        if (!evaluated) {
            return tokenPack;
        }

        if (_isFlagSet(flagsPacked, TOKEN_NOT_A_CONTRACT)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_EMPTY_BYTECODE)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_DECIMALS_REVERT)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_WEIRD_DECIMALS)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HIGH_DECIMALS)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_TOTAL_SUPPLY_REVERT)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_ZERO_TOTAL_SUPPLY)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_VERY_LOW_TOTAL_SUPPLY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_SYMBOL_REVERT)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_NAME_REVERT)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_EIP1967_PROXY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_EIP1822_PROXY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_MINIMAL_PROXY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_OWNER)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_OWNER_IS_EOA)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_PAUSABLE)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_CURRENTLY_PAUSED)) {
            tokenPack.criticalCount++;
            tokenPack.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BLACKLIST)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BLOCKLIST)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_POSSIBLE_FEE_ON_TRANSFER)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_TRANSFER_FEE_GETTER)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_TAX_FUNCTION)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_POSSIBLE_REBASING)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_MINT_CAPABILITY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BURN_CAPABILITY)) tokenPack.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_FLASH_MINT)) tokenPack.warningCount++;
    }

    function _decodeTokenFlags(uint32 flagsPacked, bool evaluated)
        internal
        pure
        returns (PolicyTokenFlagsView memory token)
    {
        token.evaluated = evaluated;
        token.notAContract = _isFlagSet(flagsPacked, TOKEN_NOT_A_CONTRACT);
        token.emptyBytecode = _isFlagSet(flagsPacked, TOKEN_EMPTY_BYTECODE);
        token.decimalsRevert = _isFlagSet(flagsPacked, TOKEN_DECIMALS_REVERT);
        token.weirdDecimals = _isFlagSet(flagsPacked, TOKEN_WEIRD_DECIMALS);
        token.highDecimals = _isFlagSet(flagsPacked, TOKEN_HIGH_DECIMALS);
        token.totalSupplyRevert = _isFlagSet(flagsPacked, TOKEN_TOTAL_SUPPLY_REVERT);
        token.zeroTotalSupply = _isFlagSet(flagsPacked, TOKEN_ZERO_TOTAL_SUPPLY);
        token.veryLowTotalSupply = _isFlagSet(flagsPacked, TOKEN_VERY_LOW_TOTAL_SUPPLY);
        token.symbolRevert = _isFlagSet(flagsPacked, TOKEN_SYMBOL_REVERT);
        token.nameRevert = _isFlagSet(flagsPacked, TOKEN_NAME_REVERT);
        token.isEip1967Proxy = _isFlagSet(flagsPacked, TOKEN_IS_EIP1967_PROXY);
        token.isEip1822Proxy = _isFlagSet(flagsPacked, TOKEN_IS_EIP1822_PROXY);
        token.isMinimalProxy = _isFlagSet(flagsPacked, TOKEN_IS_MINIMAL_PROXY);
        token.hasOwner = _isFlagSet(flagsPacked, TOKEN_HAS_OWNER);
        token.ownershipRenounced = _isFlagSet(flagsPacked, TOKEN_OWNERSHIP_RENOUNCED);
        token.ownerIsEoa = _isFlagSet(flagsPacked, TOKEN_OWNER_IS_EOA);
        token.isPausable = _isFlagSet(flagsPacked, TOKEN_IS_PAUSABLE);
        token.isCurrentlyPaused = _isFlagSet(flagsPacked, TOKEN_IS_CURRENTLY_PAUSED);
        token.hasBlacklist = _isFlagSet(flagsPacked, TOKEN_HAS_BLACKLIST);
        token.hasBlocklist = _isFlagSet(flagsPacked, TOKEN_HAS_BLOCKLIST);
        token.possibleFeeOnTransfer = _isFlagSet(flagsPacked, TOKEN_POSSIBLE_FEE_ON_TRANSFER);
        token.hasTransferFeeGetter = _isFlagSet(flagsPacked, TOKEN_HAS_TRANSFER_FEE_GETTER);
        token.hasTaxFunction = _isFlagSet(flagsPacked, TOKEN_HAS_TAX_FUNCTION);
        token.possibleRebasing = _isFlagSet(flagsPacked, TOKEN_POSSIBLE_REBASING);
        token.hasMintCapability = _isFlagSet(flagsPacked, TOKEN_HAS_MINT_CAPABILITY);
        token.hasBurnCapability = _isFlagSet(flagsPacked, TOKEN_HAS_BURN_CAPABILITY);
        token.hasPermit = _isFlagSet(flagsPacked, TOKEN_HAS_PERMIT);
        token.hasFlashMint = _isFlagSet(flagsPacked, TOKEN_HAS_FLASH_MINT);
    }
}
