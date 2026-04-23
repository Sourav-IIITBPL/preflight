// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import {PolicyKind, PolicyRiskCategory} from "../../types/OnChainTypes.sol";

/**
 * @title SVGLib
 * @author PreFlight Team
 * @notice Centralized library for constants, labels, and mapping logic used in risk report rendering.
 * @dev This library offloads large string mappings and bit-layout constants from the main renderer
 *      to ensure the renderer remains within the 24KB contract size limit.
 */
library SVGLib {
    using Strings for uint256;

    // --- Bit Layout Constants (Mirroring BaseRiskPolicy) ---

    /// @dev Bit shift for on-chain flags (32 bits)
    uint8 public constant SHIFT_ONCHAIN_FLAGS = 0;
    /// @dev Bit shift for off-chain flags (32 bits)
    uint8 public constant SHIFT_OFFCHAIN_FLAGS = 32;
    /// @dev Bit shift for the composite risk score (8 bits)
    uint8 public constant SHIFT_COMPOSITE_SCORE = 64;
    /// @dev Bit shift for the on-chain sub-score (8 bits)
    uint8 public constant SHIFT_ONCHAIN_SCORE = 72;
    /// @dev Bit shift for the off-chain sub-score (8 bits)
    uint8 public constant SHIFT_OFFCHAIN_SCORE = 80;
    /// @dev Bit shift for the final risk category (2 bits)
    uint8 public constant SHIFT_FINAL_CATEGORY = 88;
    /// @dev Bit shift for the off-chain risk category (2 bits)
    uint8 public constant SHIFT_OFFCHAIN_CATEGORY = 90;
    /// @dev Bit shift for the hard-block flag (1 bit)
    uint8 public constant SHIFT_ANY_HARD_BLOCK = 92;
    /// @dev Bit shift for the off-chain validity flag (1 bit)
    uint8 public constant SHIFT_OFFCHAIN_VALID = 93;
    /// @dev Bit shift for the on-chain critical finding count (6 bits)
    uint8 public constant SHIFT_ONCHAIN_CRITICAL = 94;
    /// @dev Bit shift for the on-chain warning count (6 bits)
    uint8 public constant SHIFT_ONCHAIN_WARNING = 100;
    /// @dev Bit shift for the off-chain finding count (6 bits)
    uint8 public constant SHIFT_OFFCHAIN_FINDINGS = 106;
    /// @dev Bit shift for price impact in basis points (16 bits)
    uint8 public constant SHIFT_PRICE_IMPACT = 112;
    /// @dev Bit shift for output discrepancy in basis points (16 bits)
    uint8 public constant SHIFT_OUTPUT_DISCREPANCY = 128;
    /// @dev Bit shift for ratio deviation in basis points (16 bits)
    uint8 public constant SHIFT_RATIO_DEVIATION = 144;
    /// @dev Bit shift for policy operation type (4 bits)
    uint8 public constant SHIFT_OPERATION = 160;
    /// @dev Bit shift for policy kind (2 bits)
    uint8 public constant SHIFT_POLICY_KIND = 164;
    /// @dev Bit shift for policy version (8 bits)
    uint8 public constant SHIFT_POLICY_VERSION = 166;
    /// @dev Bit shift for token-level risk flags (32 bits)
    uint8 public constant SHIFT_TOKEN_FLAGS = 174;
    /// @dev Bit shift for token critical count (6 bits)
    uint8 public constant SHIFT_TOKEN_CRITICAL = 206;
    /// @dev Bit shift for token warning count (6 bits)
    uint8 public constant SHIFT_TOKEN_WARNING = 212;
    /// @dev Bit shift for token evaluation flag (1 bit)
    uint8 public constant SHIFT_TOKEN_EVALUATED = 218;
    /// @dev Bit shift for economic severity tier (3 bits)
    uint8 public constant SHIFT_ECONOMIC_TIER = 219;
    /// @dev Bit shift for oracle age tier (3 bits)
    uint8 public constant SHIFT_ORACLE_AGE_TIER = 222;
    /// @dev Bit shift for excess pull tier (3 bits)
    uint8 public constant SHIFT_EXCESS_PULL_TIER = 225;
    /// @dev Bit shift for share price drift tier (3 bits)
    uint8 public constant SHIFT_SHARE_DRIFT_TIER = 228;
    /// @dev Bit shift for compound risk count (3 bits)
    uint8 public constant SHIFT_COMPOUND_COUNT = 231;
    /// @dev Bit shift for simulation revert block flag (1 bit)
    uint8 public constant SHIFT_SIM_REVERT_BLOCK = 234;
    /// @dev Bit shift for sweep severity tier (3 bits)
    uint8 public constant SHIFT_SWEEP_TIER = 235;
    /// @dev Bit shift for enhanced data presence flag (1 bit)
    uint8 public constant SHIFT_ENHANCED_PRESENT = 238;

    /// @dev The bit index within off-chain flags that indicates payload validity.
    uint8 public constant OFFCHAIN_VALID_BIT = 0;

    // --- Color Palette ---
    string public constant C_INFO = "#3fb950";
    string public constant C_WARN = "#f4b942";
    string public constant C_MED = "#f97316";
    string public constant C_CRIT = "#ef4444";
    string public constant C_ACCENT = "#38bdf8";
    string public constant C_TOKEN = "#c084fc";
    string public constant C_TEXT = "#f0f6fc";
    string public constant C_MUTED = "#8b949e";

    /**
     * @notice Maps a risk category to its corresponding UI accent color.
     * @param category The decoded risk category.
     * @return hexColor The CSS hex color string.
     */
    function getCategoryColor(PolicyRiskCategory category) public pure returns (string memory) {
        if (category == PolicyRiskCategory.INFO) return C_INFO;
        if (category == PolicyRiskCategory.WARNING) return C_WARN;
        if (category == PolicyRiskCategory.MEDIUM) return C_MED;
        return C_CRIT;
    }

    /**
     * @notice Returns a human-readable label for a risk category.
     * @param category The decoded risk category.
     * @return label The display string (e.g., "CRITICAL").
     */
    function getCategoryLabel(PolicyRiskCategory category) public pure returns (string memory) {
        if (category == PolicyRiskCategory.INFO) return "INFO";
        if (category == PolicyRiskCategory.WARNING) return "WARNING";
        if (category == PolicyRiskCategory.MEDIUM) return "MEDIUM";
        return "CRITICAL";
    }

    /**
     * @notice Returns a human-readable label for a policy kind.
     * @param kind The decoded policy kind (ERC4626, SWAP_V2, etc).
     * @return label The display string.
     */
    function getPolicyKindLabel(PolicyKind kind) public pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) return "ERC4626 Vault";
        if (kind == PolicyKind.SWAP_V2) return "V2 SWAP";
        return "V2 LIQUIDITY";
    }

    /**
     * @notice Returns a human-readable label for a specific operation within a policy.
     * @param kind The policy kind.
     * @param operation The operation index.
     * @return label The display string (e.g., "DEPOSIT", "EXACT TOKENS IN").
     */
    function getOperationLabel(PolicyKind kind, uint8 operation) public pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) {
            if (operation == 0) return "DEPOSIT";
            if (operation == 1) return "MINT";
            if (operation == 2) return "WITHDRAW";
            return "REDEEM";
        }
        if (kind == PolicyKind.SWAP_V2) {
            if (operation == 0) return "EXACT_TOKENS_IN";
            if (operation == 1) return "EXACT_TOKENS_OUT";
            if (operation == 2) return "EXACT_ETH_IN";
            if (operation == 3) return "EXACT_ETH_OUT";
            if (operation == 4) return "EXACT_TOKENS_FOR_ETH";
            return "TOKENS_FOR_EXACT_ETH";
        }

        if (operation == 0) return "ADD";
        if (operation == 1) return "ADD_ETH";
        if (operation == 2) return "REMOVE";
        return "REMOVE_ETH";
    }

    /**
     * @notice Returns the label for a specific on-chain risk flag.
     * @param kind The policy kind.
     * @param index The bit index of the flag.
     * @return label The descriptive label for the triggered finding.
     */
    function getOnChainLabel(PolicyKind kind, uint8 index) public pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) {
            if (index == 0) return "Vault Not Whitelisted";
            if (index == 1) return "Zero Supply";
            if (index == 2) return "Donation Attack";
            if (index == 3) return "Share Inflation Risk";
            if (index == 4) return "Vault Balance Mismatch";
            if (index == 5) return "Exchange Rate Anomaly";
            if (index == 6) return "Preview Revert";
            if (index == 7) return "Zero Shares Out";
            if (index == 8) return "Zero Assets Out";
            if (index == 9) return "Dust Shares";
            if (index == 10) return "Dust Assets";
            if (index == 11) return "Exceeds Max Deposit";
            if (index == 12) return "Exceeds Max Redeem";
            if (index == 13) return "Preview Convert Mismatch";
            return "";
        }
        if (kind == PolicyKind.SWAP_V2) {
            if (index == 0) return "Untrusted Router";
            if (index == 1) return "Untrusted Factory";
            if (index == 2) return "Deep Multihop";
            if (index == 3) return "Path Cycle";
            if (index == 4) return "Pool Missing";
            if (index == 5) return "Factory Mismatch";
            if (index == 6) return "Zero Liquidity";
            if (index == 7) return "Low Liquidity";
            if (index == 8) return "Low LP Supply";
            if (index == 9) return "Pool Too New";
            if (index == 10) return "Severe Imbalance";
            if (index == 11) return "K Invariant Broken";
            if (index == 12) return "High Swap Impact";
            if (index == 13) return "Flashloan Risk";
            if (index == 14) return "Price Manipulated";
            return "";
        }
        if (index == 0) return "Untrusted Router";
        if (index == 1) return "Pair Missing";
        if (index == 2) return "Zero Liquidity";
        if (index == 3) return "Low Liquidity";
        if (index == 4) return "Low LP Supply";
        if (index == 5) return "First Depositor";
        if (index == 6) return "Severe Imbalance";
        if (index == 7) return "K Invariant Broken";
        if (index == 8) return "Pool Too New";
        if (index == 9) return "Ratio Deviation";
        if (index == 10) return "High LP Impact";
        if (index == 11) return "Flashloan Risk";
        if (index == 12) return "Zero LP Out";
        if (index == 13) return "Zero Amounts Out";
        if (index == 14) return "Dust LP";
        return "";
    }

    /**
     * @notice Determines if a specific on-chain finding is considered critical for UI highlighting.
     * @param kind The policy kind.
     * @param operation The operation index.
     * @param index The bit index of the flag.
     * @return isCritical True if the finding should be rendered as critical.
     */
    function isOnChainCritical(PolicyKind kind, uint8 operation, uint8 index) public pure returns (bool) {
        if (kind == PolicyKind.ERC4626) {
            if (index == 2 || index == 4 || index == 6) return true;
            if (index == 7) return operation == 0 || operation == 1;
            if (index == 8) return operation == 2 || operation == 3;
            if (index == 11) return operation == 0 || operation == 1;
            if (index == 12) return operation == 2 || operation == 3;
            return false;
        }
        if (kind == PolicyKind.SWAP_V2) {
            return index == 3 || index == 4 || index == 6 || index == 11 || index == 14;
        }
        return index == 1 || index == 2 || index == 5 || index == 7 || index == 12 || index == 13;
    }

    /**
     * @notice Returns the label for a specific off-chain simulation risk flag.
     * @param index The bit index of the flag.
     * @return label The descriptive label.
     */
    function getOffChainLabel(uint8 index) public pure returns (string memory) {
        if (index == 1) return "Delegatecall";
        if (index == 2) return "Selfdestruct";
        if (index == 3) return "Approval Drain";
        if (index == 4) return "Owner Sweep";
        if (index == 5) return "Reentrancy";
        if (index == 6) return "Unexpected Create/Create2";
        if (index == 7) return "Upgrade Call";
        if (index == 8) return "Exit Frozen";
        if (index == 9) return "Remove Frozen";
        if (index == 10) return "First Deposit";
        if (index == 11) return "Price Impact";
        if (index == 12) return "Output Discrepancy";
        if (index == 13) return "Ratio Deviation";
        if (index == 14) return "Simulation Reverted";
        if (index == 15) return "Fee-On-Transfer Risk";
        if (index == 16) return "Stale Oracle";
        if (index == 17) return "Contract Unverified";
        if (index == 18) return "Price Deviation";
        if (index == 19) return "Excess Pull";
        if (index == 20) return "Critical Oracle";
        if (index == 21) return "Large Sweep";
        if (index == 22) return "Zero Headroom";
        if (index == 23) return "Hard Block simulation Revert";
        if (index == 24) return "Confirmed Fee-On-Transfer";
        if (index == 25) return "Share Price Drift High";
        if (index == 26) return "Honeypot";
        return "";
    }

    /**
     * @notice Determines if an off-chain finding is critical.
     * @param index The bit index of the flag.
     * @return isCritical True if the finding is critical.
     */
    function isOffChainCritical(uint8 index) public pure returns (bool) {
        return index == 1 || index == 2 || index == 3 || index == 4 || index == 5 || index == 6 || index == 7
            || index == 8 || index == 9 || index == 14 || index == 20 || index == 21 || index == 23 || index == 26;
    }

    /**
     * @notice Returns the label for a specific token-level risk flag.
     * @param index The bit index of the flag.
     * @return label The descriptive label.
     */
    function getTokenLabel(uint8 index) public pure returns (string memory) {
        if (index == 0) return "Not Contract";
        if (index == 1) return "Empty Bytecode";
        if (index == 2) return "Decimals Revert";
        if (index == 3) return "Bad Decimals";
        if (index == 4) return "High Decimals";
        if (index == 5) return "Supply Revert";
        if (index == 6) return "Zero Supply";
        if (index == 7) return "Low Supply";
        if (index == 8) return "Symbol Revert";
        if (index == 9) return "Name Revert";
        if (index == 10) return "1967 Proxy";
        if (index == 11) return "1822 Proxy";
        if (index == 12) return "Minimal Proxy";
        if (index == 13) return "Has Owner";
        if (index == 14) return "Ownership Renounced";
        if (index == 15) return "EOA Owner";
        if (index == 16) return "Pausable";
        if (index == 17) return "Paused";
        if (index == 18) return "Blacklist";
        if (index == 19) return "Blocklist";
        if (index == 20) return "Possible Fee-On-Transfer";
        if (index == 21) return "Fee Getter";
        if (index == 22) return "Tax Function";
        if (index == 23) return "Rebasing";
        if (index == 24) return "Mintable";
        if (index == 25) return "Burnable";
        if (index == 26) return "Has Permit";
        if (index == 27) return "Flash Mint";
        return "";
    }

    /**
     * @notice Determines if a token-level finding is critical.
     * @param index The bit index of the flag.
     * @return isCritical True if the finding is critical.
     */
    function isTokenCritical(uint8 index) public pure returns (bool) {
        return index == 0 || index == 1 || index == 4 || index == 5 || index == 6 || index == 17;
    }

    /**
     * @notice Returns a human-readable label for a risk severity tier (0-5).
     * @param tier The tier value (0-5).
     * @return label The display string (e.g., "HIGH", "EXTREME").
     */
    function getTierLabel(uint8 tier) public pure returns (string memory) {
        if (tier == 0) return "NONE";
        if (tier == 1) return "LOW";
        if (tier == 2) return "MEDIUM";
        if (tier == 3) return "HIGH";
        if (tier == 4) return "CRITICAL";
        return "EXTREME";
    }
}
