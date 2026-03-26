// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenGuardResult} from "../types/OnChainTypes.sol";
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

struct EnhancedCoreView {
    uint8 economicSeverityTier;
    uint8 oracleAgeTier;
    uint8 excessPullTier;
    uint8 sharePriceDriftTier;
    uint8 compoundRiskCount;
    bool simulationRevertBlock;
    uint8 sweepSeverityTier;
    bool enhancedDataPresent;
}

/**
 * @author Sourav-IITBPL
 * @notice Shared packing, scoring, and decoding utilities for PreFlight risk policies.
 */
abstract contract BaseRiskPolicy {
    error InvalidPackedKind(uint8 expectedKind, uint8 actualKind);

    struct PolicyComputation {
        PolicyRiskCategory finalCategory;
        PolicyRiskCategory offChainCategory;
        uint8 compositeScore;
        uint8 onChainScore;
        uint8 offChainScore;
        uint8 offChainFindingsCount;
        uint32 offChainFlagsPacked;
        uint8 economicSeverityTier;
        uint8 oracleAgeTier;
        uint8 excessPullTier;
        uint8 sharePriceDriftTier;
        uint8 compoundRiskCount;
        bool simulationRevertBlock;
        uint8 sweepSeverityTier;
    }

    uint8 internal constant POLICY_VERSION = 1;

    /// @dev Each on-chain critical flag (hard-block level) contributes this to onChainScore.
    uint8 internal constant W_ONCHAIN_CRITICAL = 25;

    /// @dev Each on-chain warning flag contributes this to onChainScore.
    uint8 internal constant W_ONCHAIN_WARNING = 8;

    /// @dev Off-chain riskScore contributes at most this percentage of its value.
    uint8 internal constant W_OFFCHAIN_BASE_MAX = 30;

    /// @dev Trace anomaly bonus (delegatecall / selfdestruct / approve-drain etc.).
    uint8 internal constant W_TRACE_ANOMALY = 25;

    /// @dev Honeypot detection (exit frozen, removal frozen).
    uint8 internal constant W_HONEYPOT = 40;

    /// @dev First-deposit risk .
    uint8 internal constant W_FIRST_DEPOSIT = 20;

    /// @dev Any hard-block flag on-chain also adds to composite.
    uint8 internal constant W_HARD_BLOCK_BONUS = 20;

    /// @dev Price impact / output discrepancy / drift tiers (bps).
    ///      Tier 0: clean. Tier 1: <500. Tier 2: 500-1000. Tier 3: 1000-3000. Tier 4: >3000.
    uint8 internal constant W_ECONOMIC_TIER_1 = 5;
    uint8 internal constant W_ECONOMIC_TIER_2 = 12;
    uint8 internal constant W_ECONOMIC_TIER_3 = 22;
    uint8 internal constant W_ECONOMIC_TIER_4 = 35; // forces MEDIUM at minimum

    /// @dev Oracle age tiers (seconds).
    ///      Fresh: 0. Stale 1-4 h: +5. Very stale 4-24 h: +12. Critical >24 h: +25.
    uint8 internal constant W_ORACLE_FRESH = 0;
    uint8 internal constant W_ORACLE_STALE = 5;
    uint8 internal constant W_ORACLE_VSTSTALE = 12;
    uint8 internal constant W_ORACLE_CRITICAL = 25; // also hard-block for vault oracle

    /// @dev Owner sweep tiers.
    uint8 internal constant W_SWEEP_SMALL = 10; // > 0 USD
    uint8 internal constant W_SWEEP_MEDIUM = 25; // > 100 USD equivalent
    uint8 internal constant W_SWEEP_LARGE = 40; // > 10 000 USD equivalent (hard-block)

    /// @dev Excess asset pull (vault excessPullBps) tiers.
    uint8 internal constant W_EXCESS_PULL_LOW = 8; // 100-500 bps
    uint8 internal constant W_EXCESS_PULL_MED = 20; // 500-2000 bps
    uint8 internal constant W_EXCESS_PULL_HIGH = 40; // >2000 bps (hard-block)

    /// @dev Compound risk bonus
    uint8 internal constant W_COMPOUND_BONUS = 8;

    /// @dev Input headroom tiers for exact-out swaps.
    uint8 internal constant W_HEADROOM_TIGHT = 10; // < 100 bps headroom
    uint8 internal constant W_HEADROOM_ZERO = 20; // == 0 bps

    /// @dev Confirmed FoT fee tiers.
    uint8 internal constant W_FOT_LOW = 5; // < 1%
    uint8 internal constant W_FOT_MEDIUM = 15; // 1-5%
    uint8 internal constant W_FOT_HIGH = 30; // >5%

    /// @dev Unverified contract.
    uint8 internal constant W_UNVERIFIED = 5;

    uint8 internal constant THRESHOLD_CRITICAL = 70;
    uint8 internal constant THRESHOLD_MEDIUM = 40;
    uint8 internal constant THRESHOLD_WARNING = 20;

    //Oracle age boundaries (seconds)

    uint256 internal constant ORACLE_AGE_STALE = 3_600; // 1 hour
    uint256 internal constant ORACLE_AGE_VERY_STALE = 14_400; // 4 hours
    uint256 internal constant ORACLE_AGE_CRITICAL = 86_400; // 24 hours

    // Sweep USD thresholds (18-decimal USD)

    uint256 internal constant SWEEP_USD_MEDIUM = 100e18; // $100
    uint256 internal constant SWEEP_USD_LARGE = 10_000e18; // $10,000

    uint256 internal constant BPS_TIER1 = 200;
    uint256 internal constant BPS_TIER2 = 500;
    uint256 internal constant BPS_TIER3 = 1_000;
    uint256 internal constant BPS_TIER4 = 3_000;

    uint256 internal constant EXCESS_PULL_TIER1 = 100;
    uint256 internal constant EXCESS_PULL_TIER2 = 500;
    uint256 internal constant EXCESS_PULL_TIER3 = 2_000;

    uint256 internal constant FOT_TIER1_BPS = 100; // 1%
    uint256 internal constant FOT_TIER2_BPS = 500; // 5%

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
    uint8 internal constant OFFCHAIN_EXCESS_PULL = 19;
    uint8 internal constant OFFCHAIN_ORACLE_CRITICAL = 20;
    uint8 internal constant OFFCHAIN_SWEEP_LARGE = 21;
    uint8 internal constant OFFCHAIN_HEADROOM_ZERO = 22;
    uint8 internal constant OFFCHAIN_SIM_REVERTED_HARDBLOCK = 23;
    uint8 internal constant OFFCHAIN_FEE_ON_TRANSFER_CONFIRMED = 24;
    uint8 internal constant OFFCHAIN_SHARE_PRICE_DRIFT_HIGH = 25;
    uint8 internal constant OFFCHAIN_REMOVAL_HONEYPOT = 26;

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

    uint8 internal constant SHIFT_ONCHAIN_FLAGS = 0;
    uint8 internal constant SHIFT_OFFCHAIN_FLAGS = 32;
    uint8 internal constant SHIFT_COMPOSITE_SCORE = 64;
    uint8 internal constant SHIFT_ONCHAIN_SCORE = 72;
    uint8 internal constant SHIFT_OFFCHAIN_SCORE = 80;
    uint8 internal constant SHIFT_FINAL_CATEGORY = 88;
    uint8 internal constant SHIFT_OFFCHAIN_CATEGORY = 90;
    uint8 internal constant SHIFT_ANY_HARD_BLOCK = 92;
    uint8 internal constant SHIFT_OFFCHAIN_VALID = 93;
    uint8 internal constant SHIFT_ONCHAIN_CRITICAL = 94;
    uint8 internal constant SHIFT_ONCHAIN_WARNING = 100;
    uint8 internal constant SHIFT_OFFCHAIN_FINDINGS = 106;
    uint8 internal constant SHIFT_PRICE_IMPACT = 112;
    uint8 internal constant SHIFT_OUTPUT_DISCREPANCY = 128;
    uint8 internal constant SHIFT_RATIO_DEVIATION = 144;
    uint8 internal constant SHIFT_OPERATION = 160;
    uint8 internal constant SHIFT_POLICY_KIND = 164;
    uint8 internal constant SHIFT_POLICY_VERSION = 166;
    uint8 internal constant SHIFT_TOKEN_FLAGS = 174;
    uint8 internal constant SHIFT_TOKEN_CRITICAL = 206;
    uint8 internal constant SHIFT_TOKEN_WARNING = 212;
    uint8 internal constant SHIFT_TOKEN_EVALUATED = 218;
    uint8 internal constant SHIFT_ECONOMIC_TIER = 219;
    uint8 internal constant SHIFT_ORACLE_AGE_TIER = 222;
    uint8 internal constant SHIFT_EXCESS_PULL_TIER = 225;
    uint8 internal constant SHIFT_SHARE_DRIFT_TIER = 228;
    uint8 internal constant SHIFT_COMPOUND_COUNT = 231;
    uint8 internal constant SHIFT_SIM_REVERT_BLOCK = 234;
    uint8 internal constant SHIFT_SWEEP_TIER = 235;
    uint8 internal constant SHIFT_ENHANCED_PRESENT = 238;

    /**
     * @notice Build the complete 256-bit packed risk report.
     *
     * @param kind                PolicyKind enum value.
     * @param operation           Enum value cast to uint8.
     * @param onChainCriticalCount Computed from on-chain flags.
     * @param onChainWarningCount  Computed from on-chain flags.
     * @param anyHardBlock        Any absolute hard-block flag from on-chain data.
     * @param onChainFlagsPacked  Bitmask of on-chain flags.
     * @param tokenPack           Packed token-level flags and counts.
     * @param offChain            Normalized off-chain findings.
     * @param economic            Rich numeric economic data extracted from raw bytes.
     */
    function _buildPackedPolicy(
        PolicyKind kind,
        uint8 operation,
        uint8 onChainCriticalCount,
        uint8 onChainWarningCount,
        bool anyHardBlock,
        uint32 onChainFlagsPacked,
        PolicyTokenPack memory tokenPack,
        PolicyNormalizedOffChainResult memory offChain,
        ExtendedEconomicData memory economic
    ) internal pure returns (uint256 packedReport) {
        PolicyComputation memory policy = _computePolicy(
            onChainCriticalCount, onChainWarningCount, anyHardBlock, tokenPack, offChain, economic
        );

        packedReport = uint256(onChainFlagsPacked);
        packedReport |= uint256(policy.offChainFlagsPacked) << SHIFT_OFFCHAIN_FLAGS;
        packedReport |= uint256(policy.compositeScore) << SHIFT_COMPOSITE_SCORE;
        packedReport |= uint256(policy.onChainScore) << SHIFT_ONCHAIN_SCORE;
        packedReport |= uint256(policy.offChainScore) << SHIFT_OFFCHAIN_SCORE;
        packedReport |= uint256(uint8(policy.finalCategory)) << SHIFT_FINAL_CATEGORY;
        packedReport |= uint256(uint8(policy.offChainCategory)) << SHIFT_OFFCHAIN_CATEGORY;
        packedReport |= uint256(_cap6(onChainCriticalCount)) << SHIFT_ONCHAIN_CRITICAL;
        packedReport |= uint256(_cap6(onChainWarningCount)) << SHIFT_ONCHAIN_WARNING;
        packedReport |= uint256(_cap6(policy.offChainFindingsCount)) << SHIFT_OFFCHAIN_FINDINGS;
        packedReport |= uint256(_capUint16(offChain.priceImpactBps)) << SHIFT_PRICE_IMPACT;
        packedReport |= uint256(_capUint16(offChain.outputDiscrepancyBps)) << SHIFT_OUTPUT_DISCREPANCY;
        packedReport |= uint256(_capUint16(offChain.ratioDeviationBps)) << SHIFT_RATIO_DEVIATION;
        packedReport |= uint256(operation) << SHIFT_OPERATION;
        packedReport |= uint256(uint8(kind)) << SHIFT_POLICY_KIND;
        packedReport |= uint256(POLICY_VERSION) << SHIFT_POLICY_VERSION;
        packedReport |= uint256(tokenPack.flagsPacked) << SHIFT_TOKEN_FLAGS;
        packedReport |= uint256(_cap6(tokenPack.criticalCount)) << SHIFT_TOKEN_CRITICAL;
        packedReport |= uint256(_cap6(tokenPack.warningCount)) << SHIFT_TOKEN_WARNING;

        if (anyHardBlock || tokenPack.anyHardBlock || policy.simulationRevertBlock) {
            packedReport |= uint256(1) << SHIFT_ANY_HARD_BLOCK;
        }
        if (offChain.valid) {
            packedReport |= uint256(1) << SHIFT_OFFCHAIN_VALID;
        }
        if (tokenPack.evaluated) {
            packedReport |= uint256(1) << SHIFT_TOKEN_EVALUATED;
        }

        packedReport |= uint256(_cap3(policy.economicSeverityTier)) << SHIFT_ECONOMIC_TIER;
        packedReport |= uint256(_cap3(policy.oracleAgeTier)) << SHIFT_ORACLE_AGE_TIER;
        packedReport |= uint256(_cap3(policy.excessPullTier)) << SHIFT_EXCESS_PULL_TIER;
        packedReport |= uint256(_cap3(policy.sharePriceDriftTier)) << SHIFT_SHARE_DRIFT_TIER;
        packedReport |= uint256(_cap3(policy.compoundRiskCount)) << SHIFT_COMPOUND_COUNT;
        packedReport |= uint256(_cap3(policy.sweepSeverityTier)) << SHIFT_SWEEP_TIER;
        if (policy.simulationRevertBlock) {
            packedReport |= uint256(1) << SHIFT_SIM_REVERT_BLOCK;
        }
        packedReport |= uint256(1) << SHIFT_ENHANCED_PRESENT;
    }

    function _computePolicy(
        uint8 onChainCriticalCount,
        uint8 onChainWarningCount,
        bool anyOnChainHardBlock,
        PolicyTokenPack memory tokenPack,
        PolicyNormalizedOffChainResult memory offChain,
        ExtendedEconomicData memory economicData
    ) internal pure returns (PolicyComputation memory policy) {
        uint32 offChainFlagsPacked = _packOffChainFlags(offChain, economicData);
        uint8 offChainInfoCount = _countSetBits32(_clearBit(offChainFlagsPacked, OFFCHAIN_VALID));

        bool traceAnomaly = offChain.valid
            && (offChain.hasDangerousDelegateCall
                || offChain.hasSelfDestruct
                || offChain.hasApprovalDrain
                || offChain.hasOwnerSweep
                || offChain.hasReentrancy
                || offChain.hasUnexpectedCreate
                || offChain.hasUpgradeCall);
        bool honeypot = offChain.valid && (offChain.isExitFrozen || offChain.isRemovalFrozen);

        uint256 onChainScore = uint256(onChainCriticalCount) * W_ONCHAIN_CRITICAL + uint256(onChainWarningCount)
            * W_ONCHAIN_WARNING + uint256(tokenPack.criticalCount) * W_ONCHAIN_CRITICAL
            + uint256(tokenPack.warningCount) * W_ONCHAIN_WARNING;
        onChainScore = _cap100(onChainScore);

        uint256 compositeScore = onChainScore;
        if (offChain.valid) {
            // Blend off-chain riskScore (0-100) at up to W_OFFCHAIN_BASE_MAX weight.
            compositeScore = _cap100(compositeScore + (uint256(offChain.riskScore) * W_OFFCHAIN_BASE_MAX) / 100);
        }
        if (traceAnomaly) {
            compositeScore = _addCapped(compositeScore, W_TRACE_ANOMALY);
        }
        if (honeypot) {
            compositeScore = _addCapped(compositeScore, W_HONEYPOT);
        }
        if (offChain.valid && offChain.isFirstDeposit) {
            compositeScore = _addCapped(compositeScore, W_FIRST_DEPOSIT);
        }

        bool anyHardBlock = anyOnChainHardBlock || tokenPack.anyHardBlock;
        if (anyHardBlock) {
            compositeScore = _addCapped(compositeScore, W_HARD_BLOCK_BONUS);
        }

        if (offChain.valid) {
            compositeScore = _addCapped(compositeScore, _bpsTier(economicData.priceImpactBps));

            compositeScore = _addCapped(compositeScore, _bpsTier(economicData.outputDiscrepancyBps));

            compositeScore = _addCapped(compositeScore, _bpsTier(economicData.sharePriceDriftBps));
            policy.sharePriceDriftTier = _bpsTierIndex(economicData.sharePriceDriftBps);

            compositeScore = _addCapped(compositeScore, _bpsTier(economicData.lpMintDiscrepancyBps));

            compositeScore = _addCapped(compositeScore, _bpsTier(economicData.ratioDeviationBps));

            policy.excessPullTier = _excessPullTierIndex(economicData.excessPullBps);
            compositeScore = _addCapped(compositeScore, _excessPullWeight(economicData.excessPullBps));
            if (economicData.excessPullBps > EXCESS_PULL_TIER3) {
                anyHardBlock = true;
            }

            policy.sweepSeverityTier = _sweepTierIndex(economicData.sweepAmountUSD, economicData.sweepDetected);
            compositeScore =
                _addCapped(compositeScore, _sweepWeight(economicData.sweepAmountUSD, economicData.sweepDetected));
            if (economicData.sweepDetected && economicData.sweepAmountUSD >= SWEEP_USD_LARGE) {
                anyHardBlock = true;
            }

            uint256 worstOracleAge = _worstOracleAge(economicData);
            policy.oracleAgeTier = _oracleTierIndex(worstOracleAge);
            compositeScore = _addCapped(compositeScore, _oracleAgeWeight(worstOracleAge));

            if (worstOracleAge > ORACLE_AGE_CRITICAL) {
                anyHardBlock = true;
            }

            if (economicData.feeOnTransferConfirmed) {
                compositeScore = _addCapped(compositeScore, _fotWeight(economicData.measuredFeePercent));
            }

            compositeScore = _addCapped(
                compositeScore, _headroomWeight(economicData.inputHeadroomBps, economicData.feeOnTransferConfirmed)
            );

            if (offChain.anyContractUnverified) {
                compositeScore = _addCapped(compositeScore, W_UNVERIFIED);
            }
        }

        uint8 compoundCount = _detectCompoundRisks(offChain, tokenPack, economicData, anyHardBlock);
        policy.compoundRiskCount = compoundCount;
        if (compoundCount > 0) {
            compositeScore = _addCapped(compositeScore, uint8(_min(uint256(compoundCount) * W_COMPOUND_BONUS, 40)));
        }

        bool simRevertBlock = offChain.valid && economicData.simulationReverted;
        policy.simulationRevertBlock = simRevertBlock;
        if (simRevertBlock) {
            anyHardBlock = true;
        }

        policy.economicSeverityTier = _economicSeverityTier(economicData, offChain.valid);
        bool forceCritical = anyHardBlock || traceAnomaly || honeypot || simRevertBlock;

        policy.finalCategory = _toRiskCategory(_toUint8(compositeScore), forceCritical);
        policy.offChainCategory = offChain.valid ? _toRiskCategory(offChain.riskScore, false) : PolicyRiskCategory.INFO;

        policy.compositeScore = _toUint8(compositeScore);
        policy.onChainScore = _toUint8(onChainScore);
        policy.offChainScore = offChain.valid ? offChain.riskScore : 0;
        policy.offChainFindingsCount = offChainInfoCount;
        policy.offChainFlagsPacked = offChainFlagsPacked;
    }

    function _packOffChainFlags(
        PolicyNormalizedOffChainResult memory offChain,
        ExtendedEconomicData memory economicData
    ) internal pure returns (uint32 packed) {
        if (offChain.valid) packed |= uint32(1) << OFFCHAIN_VALID;
        if (offChain.hasDangerousDelegateCall) packed |= uint32(1) << OFFCHAIN_DANGEROUS_DELEGATECALL;
        if (offChain.hasSelfDestruct) packed |= uint32(1) << OFFCHAIN_SELFDESTRUCT;
        if (offChain.hasApprovalDrain) packed |= uint32(1) << OFFCHAIN_APPROVAL_DRAIN;
        if (offChain.hasOwnerSweep) packed |= uint32(1) << OFFCHAIN_OWNER_SWEEP;
        if (offChain.hasReentrancy) packed |= uint32(1) << OFFCHAIN_REENTRANCY;
        if (offChain.hasUnexpectedCreate) packed |= uint32(1) << OFFCHAIN_UNEXPECTED_CREATE;
        if (offChain.hasUpgradeCall) packed |= uint32(1) << OFFCHAIN_UPGRADE_CALL;
        if (offChain.isExitFrozen) packed |= uint32(1) << OFFCHAIN_EXIT_FROZEN;
        if (offChain.isRemovalFrozen) packed |= uint32(1) << OFFCHAIN_REMOVAL_FROZEN;
        if (offChain.isFirstDeposit) packed |= uint32(1) << OFFCHAIN_FIRST_DEPOSIT;
        if (offChain.priceImpactBps > BPS_TIER2) packed |= uint32(1) << OFFCHAIN_PRICE_IMPACT_HIGH;
        if (offChain.outputDiscrepancyBps > BPS_TIER1) packed |= uint32(1) << OFFCHAIN_OUTPUT_DISCREPANCY_HIGH;
        if (offChain.ratioDeviationBps > BPS_TIER2) packed |= uint32(1) << OFFCHAIN_RATIO_DEVIATION_HIGH;
        if (economicData.simulationReverted) packed |= uint32(1) << OFFCHAIN_SIMULATION_REVERTED;
        if (offChain.isFeeOnTransfer) packed |= uint32(1) << OFFCHAIN_FEE_ON_TRANSFER;
        if (offChain.anyOracleStale) packed |= uint32(1) << OFFCHAIN_ORACLE_STALE;
        if (offChain.anyContractUnverified) packed |= uint32(1) << OFFCHAIN_CONTRACT_UNVERIFIED;
        if (offChain.oracleDeviation) packed |= uint32(1) << OFFCHAIN_ORACLE_DEVIATION;
        // v2 additions
        if (economicData.excessPullBps > EXCESS_PULL_TIER1) packed |= uint32(1) << OFFCHAIN_EXCESS_PULL;
        if (_worstOracleAge(economicData) > ORACLE_AGE_CRITICAL) packed |= uint32(1) << OFFCHAIN_ORACLE_CRITICAL;
        if (economicData.sweepDetected && economicData.sweepAmountUSD >= SWEEP_USD_LARGE) {
            packed |= uint32(1) << OFFCHAIN_SWEEP_LARGE;
        }
        if (economicData.inputHeadroomBps == 0 && economicData.feeOnTransferConfirmed) {
            packed |= uint32(1) << OFFCHAIN_HEADROOM_ZERO;
        }
        if (offChain.valid && economicData.simulationReverted) packed |= uint32(1) << OFFCHAIN_SIM_REVERTED_HARDBLOCK;
        if (economicData.feeOnTransferConfirmed) packed |= uint32(1) << OFFCHAIN_FEE_ON_TRANSFER_CONFIRMED;
        if (economicData.sharePriceDriftBps > BPS_TIER3) packed |= uint32(1) << OFFCHAIN_SHARE_PRICE_DRIFT_HIGH;
        // Removal honeypot confirmed: removal frozen AND simulated amounts are 0
        if (offChain.isRemovalFrozen || (economicData.removalSimAmountA == 0 && economicData.removalSimAmountB > 0)) {
            packed |= uint32(1) << OFFCHAIN_REMOVAL_HONEYPOT;
        }
    }

    function _detectCompoundRisks(
        PolicyNormalizedOffChainResult memory offChain,
        PolicyTokenPack memory tokenPack,
        ExtendedEconomicData memory eco,
        bool anyHardBlock
    ) internal pure returns (uint8 count) {
        if (!offChain.valid) return 0;

        // C1: delegatecall WITHOUT a known upgrade call -> unknown delegatecall target
        if (offChain.hasDangerousDelegateCall && !offChain.hasUpgradeCall) count++;

        // C2: approval drain + reentrancy = chained attack
        if (offChain.hasApprovalDrain && offChain.hasReentrancy) count++;

        // C3: owner sweep that is large
        if (eco.sweepDetected && eco.sweepAmountUSD >= SWEEP_USD_MEDIUM) count++;

        // C4: simulation reverted AND cannot exit (honeypot is confirmed with no way out)
        if (eco.simulationReverted && (offChain.isExitFrozen || offChain.isRemovalFrozen)) count++;

        // C5: token is currently paused AND there's a critical on-chain flag
        if (_isFlagSet(tokenPack.flagsPacked, TOKEN_IS_CURRENTLY_PAUSED) && anyHardBlock) count++;

        // C6: confirmed FoT + rebasing token together (vault/LP accounting breaks completely)
        if (eco.feeOnTransferConfirmed && _isFlagSet(tokenPack.flagsPacked, TOKEN_POSSIBLE_REBASING)) count++;

        // C7: oracle stale AND oracle deviation (unknown price AND price is wrong)
        if (offChain.anyOracleStale && offChain.oracleDeviation) count++;

        // C8: upgrade call + owner sweep = upgrade-to-drain pattern
        if (offChain.hasUpgradeCall && offChain.hasOwnerSweep) count++;

        // C9: excess pull + exit frozen = pulled extra AND can't get funds out
        if (eco.excessPullBps > EXCESS_PULL_TIER2 && offChain.isExitFrozen) count++;

        // C10: high share price drift with no simulation revert -> stealth manipulation
        if (eco.sharePriceDriftBps > BPS_TIER3 && !eco.simulationReverted) count++;

        if (count > 7) count = 7; // cap for 3-bit field
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
        core.offChainInfoCount = uint8(_extract(packedReport, SHIFT_OFFCHAIN_FINDINGS, 6));
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
        if (actualKind != expectedKind) revert InvalidPackedKind(uint8(expectedKind), uint8(actualKind));
    }

    function _bpsTier(uint256 bps) internal pure returns (uint8) {
        if (bps == 0) return 0;
        if (bps < BPS_TIER1) return W_ECONOMIC_TIER_1 / 2; // < 200 bps = minor
        if (bps < BPS_TIER2) return W_ECONOMIC_TIER_1; // 200-500
        if (bps < BPS_TIER3) return W_ECONOMIC_TIER_2; // 500-1000
        if (bps < BPS_TIER4) return W_ECONOMIC_TIER_3; // 1000-3000
        return W_ECONOMIC_TIER_4; // >3000
    }

    function _bpsTierIndex(uint256 bps) internal pure returns (uint8) {
        if (bps == 0) return 0;
        if (bps < BPS_TIER1) return 1;
        if (bps < BPS_TIER2) return 2;
        if (bps < BPS_TIER3) return 3;
        if (bps < BPS_TIER4) return 4;
        return 5;
    }

    function _excessPullWeight(uint256 excessPullBps) internal pure returns (uint8) {
        if (excessPullBps == 0) return 0;
        if (excessPullBps < EXCESS_PULL_TIER1) return 0;
        if (excessPullBps < EXCESS_PULL_TIER2) return W_EXCESS_PULL_LOW;
        if (excessPullBps < EXCESS_PULL_TIER3) return W_EXCESS_PULL_MED;
        return W_EXCESS_PULL_HIGH;
    }

    function _excessPullTierIndex(uint256 bps) internal pure returns (uint8) {
        if (bps < EXCESS_PULL_TIER1) return 0;
        if (bps < EXCESS_PULL_TIER2) return 1;
        if (bps < EXCESS_PULL_TIER3) return 2;
        return 3;
    }

    function _sweepWeight(uint256 sweepUSD, bool detected) internal pure returns (uint8) {
        if (!detected) return 0;
        if (sweepUSD == 0) return W_SWEEP_SMALL;
        if (sweepUSD < SWEEP_USD_MEDIUM) return W_SWEEP_SMALL;
        if (sweepUSD < SWEEP_USD_LARGE) return W_SWEEP_MEDIUM;
        return W_SWEEP_LARGE;
    }

    function _sweepTierIndex(uint256 sweepUSD, bool detected) internal pure returns (uint8) {
        if (!detected || sweepUSD == 0) return 0;
        if (sweepUSD < SWEEP_USD_MEDIUM) return 1;
        if (sweepUSD < SWEEP_USD_LARGE) return 2;
        return 3;
    }

    function _oracleAgeWeight(uint256 ageSecs) internal pure returns (uint8) {
        if (ageSecs < ORACLE_AGE_STALE) return W_ORACLE_FRESH;
        if (ageSecs < ORACLE_AGE_VERY_STALE) return W_ORACLE_STALE;
        if (ageSecs < ORACLE_AGE_CRITICAL) return W_ORACLE_VSTSTALE;
        return W_ORACLE_CRITICAL;
    }

    function _oracleTierIndex(uint256 ageSecs) internal pure returns (uint8) {
        if (ageSecs < ORACLE_AGE_STALE) return 0;
        if (ageSecs < ORACLE_AGE_VERY_STALE) return 1;
        if (ageSecs < ORACLE_AGE_CRITICAL) return 2;
        return 3;
    }

    function _worstOracleAge(ExtendedEconomicData memory economicData) internal pure returns (uint256 worst) {
        worst = economicData.assetOracleAge;
        if (economicData.tokenInOracleAge > worst) worst = economicData.tokenInOracleAge;
        if (economicData.tokenOutOracleAge > worst) worst = economicData.tokenOutOracleAge;
        if (economicData.tokenAOracleAge > worst) worst = economicData.tokenAOracleAge;
        if (economicData.tokenBOracleAge > worst) worst = economicData.tokenBOracleAge;
    }

    function _fotWeight(uint256 measuredFeePercent) internal pure returns (uint8) {
        if (measuredFeePercent == 0) return 0;
        if (measuredFeePercent < FOT_TIER1_BPS) return W_FOT_LOW;
        if (measuredFeePercent < FOT_TIER2_BPS) return W_FOT_MEDIUM;
        return W_FOT_HIGH;
    }

    function _headroomWeight(uint256 headroomBps, bool isFot) internal pure returns (uint8) {
        if (isFot) return 0; // FoT swaps should use exact-in; headroom doesn't apply
        if (headroomBps == 0) return W_HEADROOM_ZERO;
        if (headroomBps < 100) return W_HEADROOM_TIGHT;
        return 0;
    }

    /// @dev Combines all economic signals into a single 0-7 severity tier.
    function _economicSeverityTier(ExtendedEconomicData memory economicData, bool valid) internal pure returns (uint8) {
        if (!valid) return 0;
        uint256 maxBps = economicData.outputDiscrepancyBps;
        if (economicData.sharePriceDriftBps > maxBps) maxBps = economicData.sharePriceDriftBps;
        if (economicData.priceImpactBps > maxBps) maxBps = economicData.priceImpactBps;
        if (economicData.lpMintDiscrepancyBps > maxBps) maxBps = economicData.lpMintDiscrepancyBps;
        if (economicData.ratioDeviationBps > maxBps) maxBps = economicData.ratioDeviationBps;

        uint8 idx = _bpsTierIndex(maxBps);
        if (economicData.simulationReverted) idx = idx < 6 ? idx + 1 : 7;
        if (economicData.excessPullBps > EXCESS_PULL_TIER3) idx = 7;
        return idx > 7 ? 7 : idx;
    }

    function _packTokenFlags(TokenGuardResult memory tokenResult) internal pure returns (uint32 packedResult) {
        if (tokenResult.NOT_A_CONTRACT) packedResult |= uint32(1) << TOKEN_NOT_A_CONTRACT;
        if (tokenResult.EMPTY_BYTECODE) packedResult |= uint32(1) << TOKEN_EMPTY_BYTECODE;
        if (tokenResult.DECIMALS_REVERT) packedResult |= uint32(1) << TOKEN_DECIMALS_REVERT;
        if (tokenResult.WEIRD_DECIMALS) packedResult |= uint32(1) << TOKEN_WEIRD_DECIMALS;
        if (tokenResult.HIGH_DECIMALS) packedResult |= uint32(1) << TOKEN_HIGH_DECIMALS;
        if (tokenResult.TOTAL_SUPPLY_REVERT) packedResult |= uint32(1) << TOKEN_TOTAL_SUPPLY_REVERT;
        if (tokenResult.ZERO_TOTAL_SUPPLY) packedResult |= uint32(1) << TOKEN_ZERO_TOTAL_SUPPLY;
        if (tokenResult.VERY_LOW_TOTAL_SUPPLY) packedResult |= uint32(1) << TOKEN_VERY_LOW_TOTAL_SUPPLY;
        if (tokenResult.SYMBOL_REVERT) packedResult |= uint32(1) << TOKEN_SYMBOL_REVERT;
        if (tokenResult.NAME_REVERT) packedResult |= uint32(1) << TOKEN_NAME_REVERT;
        if (tokenResult.IS_EIP1967_PROXY) packedResult |= uint32(1) << TOKEN_IS_EIP1967_PROXY;
        if (tokenResult.IS_EIP1822_PROXY) packedResult |= uint32(1) << TOKEN_IS_EIP1822_PROXY;
        if (tokenResult.IS_MINIMAL_PROXY) packedResult |= uint32(1) << TOKEN_IS_MINIMAL_PROXY;
        if (tokenResult.HAS_OWNER) packedResult |= uint32(1) << TOKEN_HAS_OWNER;
        if (tokenResult.OWNERSHIP_RENOUNCED) packedResult |= uint32(1) << TOKEN_OWNERSHIP_RENOUNCED;
        if (tokenResult.OWNER_IS_EOA) packedResult |= uint32(1) << TOKEN_OWNER_IS_EOA;
        if (tokenResult.IS_PAUSABLE) packedResult |= uint32(1) << TOKEN_IS_PAUSABLE;
        if (tokenResult.IS_CURRENTLY_PAUSED) packedResult |= uint32(1) << TOKEN_IS_CURRENTLY_PAUSED;
        if (tokenResult.HAS_BLACKLIST) packedResult |= uint32(1) << TOKEN_HAS_BLACKLIST;
        if (tokenResult.HAS_BLOCKLIST) packedResult |= uint32(1) << TOKEN_HAS_BLOCKLIST;
        if (tokenResult.POSSIBLE_FEE_ON_TRANSFER) packedResult |= uint32(1) << TOKEN_POSSIBLE_FEE_ON_TRANSFER;
        if (tokenResult.HAS_TRANSFER_FEE_GETTER) packedResult |= uint32(1) << TOKEN_HAS_TRANSFER_FEE_GETTER;
        if (tokenResult.HAS_TAX_FUNCTION) packedResult |= uint32(1) << TOKEN_HAS_TAX_FUNCTION;
        if (tokenResult.POSSIBLE_REBASING) packedResult |= uint32(1) << TOKEN_POSSIBLE_REBASING;
        if (tokenResult.HAS_MINT_CAPABILITY) packedResult |= uint32(1) << TOKEN_HAS_MINT_CAPABILITY;
        if (tokenResult.HAS_BURN_CAPABILITY) packedResult |= uint32(1) << TOKEN_HAS_BURN_CAPABILITY;
        if (tokenResult.HAS_PERMIT) packedResult |= uint32(1) << TOKEN_HAS_PERMIT;
        if (tokenResult.HAS_FLASH_MINT) packedResult |= uint32(1) << TOKEN_HAS_FLASH_MINT;
    }

    function _toTokenPack(uint32 flagsPacked, bool evaluated)
        internal
        pure
        returns (PolicyTokenPack memory tokenPacked)
    {
        tokenPacked.flagsPacked = flagsPacked;
        tokenPacked.evaluated = evaluated;
        if (!evaluated) return tokenPacked;

        if (_isFlagSet(flagsPacked, TOKEN_NOT_A_CONTRACT)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_EMPTY_BYTECODE)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_HIGH_DECIMALS)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_TOTAL_SUPPLY_REVERT)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_ZERO_TOTAL_SUPPLY)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }
        if (_isFlagSet(flagsPacked, TOKEN_IS_CURRENTLY_PAUSED)) {
            tokenPacked.criticalCount++;
            tokenPacked.anyHardBlock = true;
        }

        if (_isFlagSet(flagsPacked, TOKEN_DECIMALS_REVERT)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_WEIRD_DECIMALS)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_VERY_LOW_TOTAL_SUPPLY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_SYMBOL_REVERT)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_NAME_REVERT)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_EIP1967_PROXY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_EIP1822_PROXY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_MINIMAL_PROXY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_OWNER)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_OWNER_IS_EOA)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_IS_PAUSABLE)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BLACKLIST)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BLOCKLIST)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_POSSIBLE_FEE_ON_TRANSFER)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_TRANSFER_FEE_GETTER)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_TAX_FUNCTION)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_POSSIBLE_REBASING)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_MINT_CAPABILITY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_BURN_CAPABILITY)) tokenPacked.warningCount++;
        if (_isFlagSet(flagsPacked, TOKEN_HAS_FLASH_MINT)) tokenPacked.warningCount++;
    }

    function _decodeTokenFlags(uint32 packed, bool evaluated)
        internal
        pure
        returns (PolicyTokenFlagsView memory tokenFlags)
    {
        tokenFlags.evaluated = evaluated;
        tokenFlags.notAContract = _isFlagSet(packed, TOKEN_NOT_A_CONTRACT);
        tokenFlags.emptyBytecode = _isFlagSet(packed, TOKEN_EMPTY_BYTECODE);
        tokenFlags.decimalsRevert = _isFlagSet(packed, TOKEN_DECIMALS_REVERT);
        tokenFlags.weirdDecimals = _isFlagSet(packed, TOKEN_WEIRD_DECIMALS);
        tokenFlags.highDecimals = _isFlagSet(packed, TOKEN_HIGH_DECIMALS);
        tokenFlags.totalSupplyRevert = _isFlagSet(packed, TOKEN_TOTAL_SUPPLY_REVERT);
        tokenFlags.zeroTotalSupply = _isFlagSet(packed, TOKEN_ZERO_TOTAL_SUPPLY);
        tokenFlags.veryLowTotalSupply = _isFlagSet(packed, TOKEN_VERY_LOW_TOTAL_SUPPLY);
        tokenFlags.symbolRevert = _isFlagSet(packed, TOKEN_SYMBOL_REVERT);
        tokenFlags.nameRevert = _isFlagSet(packed, TOKEN_NAME_REVERT);
        tokenFlags.isEip1967Proxy = _isFlagSet(packed, TOKEN_IS_EIP1967_PROXY);
        tokenFlags.isEip1822Proxy = _isFlagSet(packed, TOKEN_IS_EIP1822_PROXY);
        tokenFlags.isMinimalProxy = _isFlagSet(packed, TOKEN_IS_MINIMAL_PROXY);
        tokenFlags.hasOwner = _isFlagSet(packed, TOKEN_HAS_OWNER);
        tokenFlags.ownershipRenounced = _isFlagSet(packed, TOKEN_OWNERSHIP_RENOUNCED);
        tokenFlags.ownerIsEoa = _isFlagSet(packed, TOKEN_OWNER_IS_EOA);
        tokenFlags.isPausable = _isFlagSet(packed, TOKEN_IS_PAUSABLE);
        tokenFlags.isCurrentlyPaused = _isFlagSet(packed, TOKEN_IS_CURRENTLY_PAUSED);
        tokenFlags.hasBlacklist = _isFlagSet(packed, TOKEN_HAS_BLACKLIST);
        tokenFlags.hasBlocklist = _isFlagSet(packed, TOKEN_HAS_BLOCKLIST);
        tokenFlags.possibleFeeOnTransfer = _isFlagSet(packed, TOKEN_POSSIBLE_FEE_ON_TRANSFER);
        tokenFlags.hasTransferFeeGetter = _isFlagSet(packed, TOKEN_HAS_TRANSFER_FEE_GETTER);
        tokenFlags.hasTaxFunction = _isFlagSet(packed, TOKEN_HAS_TAX_FUNCTION);
        tokenFlags.possibleRebasing = _isFlagSet(packed, TOKEN_POSSIBLE_REBASING);
        tokenFlags.hasMintCapability = _isFlagSet(packed, TOKEN_HAS_MINT_CAPABILITY);
        tokenFlags.hasBurnCapability = _isFlagSet(packed, TOKEN_HAS_BURN_CAPABILITY);
        tokenFlags.hasPermit = _isFlagSet(packed, TOKEN_HAS_PERMIT);
        tokenFlags.hasFlashMint = _isFlagSet(packed, TOKEN_HAS_FLASH_MINT);
    }

    function _decodeEnhanced(uint256 packedReport) internal pure returns (EnhancedCoreView memory coreView) {
        coreView.economicSeverityTier = uint8(_extract(packedReport, SHIFT_ECONOMIC_TIER, 3));
        coreView.oracleAgeTier = uint8(_extract(packedReport, SHIFT_ORACLE_AGE_TIER, 3));
        coreView.excessPullTier = uint8(_extract(packedReport, SHIFT_EXCESS_PULL_TIER, 3));
        coreView.sharePriceDriftTier = uint8(_extract(packedReport, SHIFT_SHARE_DRIFT_TIER, 3));
        coreView.compoundRiskCount = uint8(_extract(packedReport, SHIFT_COMPOUND_COUNT, 3));
        coreView.simulationRevertBlock = _extract(packedReport, SHIFT_SIM_REVERT_BLOCK, 1) == 1;
        coreView.sweepSeverityTier = uint8(_extract(packedReport, SHIFT_SWEEP_TIER, 3));
        coreView.enhancedDataPresent = _extract(packedReport, SHIFT_ENHANCED_PRESENT, 1) == 1;
    }

    //  Utility helpers

    function _toRiskCategory(uint8 score, bool forceCritical) internal pure returns (PolicyRiskCategory) {
        if (forceCritical || score >= THRESHOLD_CRITICAL) return PolicyRiskCategory.CRITICAL;
        if (score >= THRESHOLD_MEDIUM) return PolicyRiskCategory.MEDIUM;
        if (score >= THRESHOLD_WARNING) return PolicyRiskCategory.WARNING;
        return PolicyRiskCategory.INFO;
    }

    function _extract(uint256 p, uint8 shift, uint8 width) internal pure returns (uint256) {
        return (p >> shift) & ((uint256(1) << width) - 1);
    }

    function _isFlagSet(uint32 packed, uint8 bit) internal pure returns (bool) {
        return ((packed >> bit) & uint32(1)) == 1;
    }

    function _countSetBits32(uint32 v) internal pure returns (uint8 count) {
        while (v != 0) if ((v & 1) == 1) count++;
        v >>= 1;
    }

    function _clearBit(uint32 v, uint8 bit) internal pure returns (uint32) {
        return v & ~(uint32(1) << bit);
    }

    function _cap100(uint256 v) internal pure returns (uint256) {
        return v > 100 ? 100 : v;
    }

    function _cap6(uint8 v) internal pure returns (uint8) {
        return v > 63 ? 63 : v;
    }

    function _cap3(uint8 v) internal pure returns (uint8) {
        return v > 7 ? 7 : v;
    }

    function _addCapped(uint256 base, uint8 add) internal pure returns (uint256) {
        return _cap100(base + uint256(add));
    }

    function _toUint8(uint256 v) internal pure returns (uint8) {
        return v > 255 ? 255 : uint8(v);
    }

    function _capRiskScore(uint256 v) internal pure returns (uint8) {
        return uint8(v > 100 ? 100 : v);
    }

    function _capUint16(uint256 v) internal pure returns (uint16) {
        return uint16(v > 65535 ? 65535 : v);
    }

    function _max3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 m = a > b ? a : b;
        return m > c ? m : c;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Build an empty ExtendedEconomicData (all zeros / false).
    function _emptyEco() internal pure returns (ExtendedEconomicData memory eco) {}
}
