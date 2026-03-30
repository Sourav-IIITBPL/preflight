// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Canonical on-chain risk flags produced by the ERC-4626 vault guard.
struct VaultGuardResult {
    bool VAULT_NOT_WHITELISTED;
    bool VAULT_ZERO_SUPPLY;
    bool DONATION_ATTACK;
    bool SHARE_INFLATION_RISK;
    bool VAULT_BALANCE_MISMATCH;
    bool EXCHANGE_RATE_ANOMALY;
    bool PREVIEW_REVERT;
    bool ZERO_SHARES_OUT;
    bool ZERO_ASSETS_OUT;
    bool DUST_SHARES;
    bool DUST_ASSETS;
    bool EXCEEDS_MAX_DEPOSIT;
    bool EXCEEDS_MAX_REDEEM;
    bool PREVIEW_CONVERT_MISMATCH;
    TokenGuardResult tokenResult;
}

/// @notice Canonical on-chain risk flags produced by the Uniswap V2 liquidity guard.
struct LiquidityV2GuardResult {
    bool ROUTER_NOT_TRUSTED;
    bool PAIR_NOT_EXISTS;
    bool ZERO_LIQUIDITY;
    bool LOW_LIQUIDITY;
    bool LOW_LP_SUPPLY;
    bool FIRST_DEPOSITOR_RISK;
    bool SEVERE_IMBALANCE;
    bool K_INVARIANT_BROKEN;
    bool POOL_TOO_NEW;
    bool AMOUNT_RATIO_DEVIATION;
    bool HIGH_LP_IMPACT;
    bool FLASHLOAN_RISK;
    bool ZERO_LP_OUT;
    bool ZERO_AMOUNTS_OUT;
    bool DUST_LP;
    TokenGuardResult tokenAResult;
    TokenGuardResult tokenBResult;
}

/// @notice Canonical on-chain risk flags produced by the Uniswap V2 swap guard.
struct SwapV2GuardResult {
    bool ROUTER_NOT_TRUSTED;
    bool FACTORY_NOT_TRUSTED;
    bool DEEP_MULTIHOP;
    bool DUPLICATE_TOKEN_IN_PATH;
    bool POOL_NOT_EXISTS;
    bool FACTORY_MISMATCH;
    bool ZERO_LIQUIDITY;
    bool LOW_LIQUIDITY;
    bool LOW_LP_SUPPLY;
    bool POOL_TOO_NEW;
    bool SEVERE_IMBALANCE;
    bool K_INVARIANT_BROKEN;
    bool HIGH_SWAP_IMPACT;
    bool FLASHLOAN_RISK;
    bool PRICE_MANIPULATED;
    TokenGuardResult[] tokenResult;
}

/// @notice Canonical token-level risk flags produced by the token guard.
struct TokenGuardResult {
    bool NOT_A_CONTRACT;
    bool EMPTY_BYTECODE;
    bool DECIMALS_REVERT;
    bool WEIRD_DECIMALS;
    bool HIGH_DECIMALS;
    bool TOTAL_SUPPLY_REVERT;
    bool ZERO_TOTAL_SUPPLY;
    bool VERY_LOW_TOTAL_SUPPLY;
    bool SYMBOL_REVERT;
    bool NAME_REVERT;
    bool IS_EIP1967_PROXY;
    bool IS_EIP1822_PROXY;
    bool IS_MINIMAL_PROXY;
    bool HAS_OWNER;
    bool OWNERSHIP_RENOUNCED;
    bool OWNER_IS_EOA;
    bool IS_PAUSABLE;
    bool IS_CURRENTLY_PAUSED;
    bool HAS_BLACKLIST;
    bool HAS_BLOCKLIST;
    bool POSSIBLE_FEE_ON_TRANSFER;
    bool HAS_TRANSFER_FEE_GETTER;
    bool HAS_TAX_FUNCTION;
    bool POSSIBLE_REBASING;
    bool HAS_MINT_CAPABILITY;
    bool HAS_BURN_CAPABILITY;
    bool HAS_PERMIT;
    bool HAS_FLASH_MINT;
}

/// @notice Final categorical severity assigned to a packed policy report.
enum PolicyRiskCategory {
    INFO,
    WARNING,
    MEDIUM,
    CRITICAL
}

/// @notice Identifies which policy family produced a packed risk report.
enum PolicyKind {
    ERC4626,
    SWAP_V2,
    LIQUIDITY_V2
}

/// @notice Normalized economic findings shared across policy families.
struct ExtendedEconomicData {
    // Vault-specific
    uint256 outputDiscrepancyBps;
    uint256 sharePriceDriftBps;
    uint256 excessPullBps;
    uint256 assetOracleAge;
    uint256 exitSimulatedOut;
    uint256 sweepAmountUSD;
    // Swap-specific
    uint256 priceImpactBps;
    uint256 measuredFeePercent;
    uint256 inputHeadroomBps;
    uint256 tokenInOracleAge;
    uint256 tokenOutOracleAge;
    uint256 oracleFairAmountOut;
    uint256 actualAmountOut;
    //Liquidity-specific
    uint256 lpMintDiscrepancyBps;
    uint256 ratioDeviationBps;
    uint256 excessValueLostUSD;
    uint256 tokenAOracleAge;
    uint256 tokenBOracleAge;
    uint256 removalSimAmountA;
    uint256 removalSimAmountB;
    // Universal
    bool simulationReverted;
    bool isExitFrozen;
    bool isRemovalFrozen;
    bool sweepDetected;
    bool upgradeCallDetected;
    bool feeOnTransferConfirmed;
}

/// @notice Shared normalized off-chain findings used during policy scoring.
struct PolicyNormalizedOffChainResult {
    bool valid;
    uint8 riskScore;
    bool hasDangerousDelegateCall;
    bool hasSelfDestruct;
    bool hasApprovalDrain;
    bool hasOwnerSweep;
    bool hasReentrancy;
    bool hasUnexpectedCreate;
    bool hasUpgradeCall;
    bool isExitFrozen;
    bool isRemovalFrozen;
    bool isFirstDeposit;
    bool isFeeOnTransfer;
    bool anyOracleStale;
    bool anyContractUnverified;
    bool oracleDeviation;
    bool simulationReverted;
    uint16 priceImpactBps;
    uint16 outputDiscrepancyBps;
    uint16 ratioDeviationBps;
}

/// @notice Decoded core report fields common to every policy family.
struct PolicyCoreView {
    PolicyKind kind;
    uint8 operation;
    uint8 version;
    PolicyRiskCategory finalCategory;
    PolicyRiskCategory offChainCategory;
    uint8 compositeScore;
    uint8 onChainScore;
    uint8 offChainScore;
    uint8 onChainCriticalCount;
    uint8 onChainWarningCount;
    uint8 offChainInfoCount;
    bool anyHardBlock;
    bool offChainValid;
    uint32 onChainFlagsPacked;
    uint32 offChainFlagsPacked;
    uint32 tokenFlagsPacked;
    uint16 priceImpactBps;
    uint16 outputDiscrepancyBps;
    uint16 ratioDeviationBps;
    uint8 tokenCriticalCount;
    uint8 tokenWarningCount;
    bool tokenRiskEvaluated;
}

/// @notice Decoded off-chain boolean findings common to every policy family.
struct PolicyOffChainView {
    bool hasDangerousDelegateCall;
    bool hasSelfDestruct;
    bool hasApprovalDrain;
    bool hasOwnerSweep;
    bool hasReentrancy;
    bool hasUnexpectedCreate;
    bool hasUpgradeCall;
    bool isExitFrozen;
    bool isRemovalFrozen;
    bool isFirstDeposit;
    bool isFeeOnTransfer;
    bool anyOracleStale;
    bool anyContractUnverified;
    bool oracleDeviation;
    bool simulationReverted;
}

/// @notice Packed on-chain findings plus aggregated counts used during policy construction.
struct PolicyOnChainPack {
    uint32 flagsPacked;
    uint32 tokenFlagsPacked;
    uint8 criticalCount;
    uint8 warningCount;
    uint8 tokenCriticalCount;
    uint8 tokenWarningCount;
    bool anyHardBlock;
}

/// @notice Packed token-risk findings plus aggregated counts used during policy construction.
struct PolicyTokenPack {
    uint32 flagsPacked;
    uint8 criticalCount;
    uint8 warningCount;
    bool anyHardBlock;
    bool evaluated;
}

/// @notice Decoded token-risk flags shared across policy families.
struct PolicyTokenFlagsView {
    bool evaluated;
    bool notAContract;
    bool emptyBytecode;
    bool decimalsRevert;
    bool weirdDecimals;
    bool highDecimals;
    bool totalSupplyRevert;
    bool zeroTotalSupply;
    bool veryLowTotalSupply;
    bool symbolRevert;
    bool nameRevert;
    bool isEip1967Proxy;
    bool isEip1822Proxy;
    bool isMinimalProxy;
    bool hasOwner;
    bool ownershipRenounced;
    bool ownerIsEoa;
    bool isPausable;
    bool isCurrentlyPaused;
    bool hasBlacklist;
    bool hasBlocklist;
    bool possibleFeeOnTransfer;
    bool hasTransferFeeGetter;
    bool hasTaxFunction;
    bool possibleRebasing;
    bool hasMintCapability;
    bool hasBurnCapability;
    bool hasPermit;
    bool hasFlashMint;
}
