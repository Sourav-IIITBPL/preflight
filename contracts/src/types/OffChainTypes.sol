// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Enumerates the ERC-4626 vault operations evaluated off-chain.
enum VaultOpType {
    DEPOSIT,
    MINT,
    WITHDRAW,
    REDEEM
}

/// @notice Enumerates the swap execution modes evaluated off-chain.
enum SwapOpType {
    EXACT_TOKENS_IN,
    EXACT_TOKENS_OUT,
    EXACT_ETH_IN,
    EXACT_ETH_OUT,
    EXACT_TOKENS_FOR_ETH,
    TOKENS_FOR_EXACT_ETH
}

/// @notice Enumerates the liquidity execution modes evaluated off-chain.
enum LiquidityOpType {
    ADD,
    ADD_ETH,
    REMOVE,
    REMOVE_ETH
}

/// @notice Coarse off-chain severity classification emitted by simulation tooling.
enum RiskLevel {
    SAFE,
    WARNING,
    CRITICAL
}

/// @notice Enumerates low-level EVM trace node types captured during simulation.
enum TraceType {
    CALL,
    DELEGATECALL,
    STATICCALL,
    CREATE,
    CREATE2,
    SELFDESTRUCT
}

/// @notice Recursive execution trace node captured from off-chain simulation.
struct TraceEntry {
    TraceType traceType;
    address from;
    address to;
    uint256 value;
    bytes input;
    bytes output;
    uint256 gas;
    uint256 gasUsed;
    string error;
    TraceEntry[] calls;
}

/// @notice Shared trace-level findings reused across multiple simulation result types.
struct SharedTraceFindings {
    bool hasDangerousDelegateCall;
    address delegateCallTarget;
    bool hasSelfDestruct;
    bool hasUnexpectedCreate;
    address[] createAddresses;
    bool hasApprovalDrain;
    address approvalDrainSpender;
    bool hasReentrancy;
    address reentrancyAddress;
}

/// @notice ERC-4626-specific trace findings extracted from simulation.
struct VaultTraceFindings {
    bool hasDangerousDelegateCall;
    address delegateCallTarget;
    bool hasSelfDestruct;
    bool hasUnexpectedCreate;
    address[] createAddresses;
    bool hasApprovalDrain;
    address approvalDrainSpender;
    bool hasReentrancy;
    address reentrancyAddress;
    bool hasOwnerSweep;
    uint256 sweepAmount;
    address sweepToken;
    bool hasUpgradeCall;
    address upgradeTarget;
}

/// @notice ERC-4626-specific economic findings extracted from simulation.
struct VaultEconomicFindings {
    bool simulationReverted;
    string revertReason;
    uint256 primaryOutput;
    uint256 primaryExpected;
    uint256 outputDiscrepancyBps;
    uint256 sharePriceBefore;
    uint256 sharePriceAfter;
    uint256 sharePriceDriftBps;
    bool isExitFrozen;
    string exitRevertReason;
    uint256 exitSimulatedOut;
    uint256 actualAssetPull;
    uint256 excessPullBps;
    uint256 assetPriceUSD;
    bool assetOracleStale;
    uint256 assetOracleAge;
}

/// @notice Full off-chain simulation output for an ERC-4626 operation.
struct VaultOffChainResult {
    bool isSafe;
    RiskLevel riskLevel;
    uint256 riskScore;
    VaultOpType operation;
    VaultTraceFindings trace;
    VaultEconomicFindings economic;
    bool vaultVerified;
    bool assetVerified;
    uint256 simulatedAt;
    string network;
}

/// @notice Swap-specific trace findings extracted from simulation.
struct SwapTraceFindings {
    bool hasDangerousDelegateCall;
    address delegateCallTarget;
    bool hasSelfDestruct;
    bool hasUnexpectedCreate;
    address[] createAddresses;
    bool hasApprovalDrain;
    address approvalDrainSpender;
    bool hasReentrancy;
    address reentrancyAddress;
}

/// @notice Swap-specific economic findings extracted from simulation.
struct SwapEconomicFindings {
    bool simulationReverted;
    string revertReason;
    uint256 actualAmountIn;
    uint256 actualAmountOut;
    uint256 inputHeadroomBps;
    uint256 ethRefunded;
    uint256 oracleFairAmountOut;
    uint256 priceImpactBps;
    bool oracleDeviation;
    bool isFeeOnTransfer;
    uint256 measuredFeePercent;
    uint256 tokenInPriceUSD;
    uint256 tokenOutPriceUSD;
    bool tokenInOracleStale;
    bool tokenOutOracleStale;
    uint256 tokenInOracleAge;
    uint256 tokenOutOracleAge;
}

/// @notice Full off-chain simulation output for a swap operation.
struct SwapOffChainResult {
    bool isSafe;
    RiskLevel riskLevel;
    uint256 riskScore;
    SwapOpType operation;
    SwapTraceFindings trace;
    SwapEconomicFindings economic;
    bool routerVerified;
    bool tokenInVerified;
    bool tokenOutVerified;
    uint256 simulatedAt;
    string network;
}

/// @notice Liquidity-specific trace findings extracted from simulation.
struct LiquidityTraceFindings {
    bool hasDangerousDelegateCall;
    address delegateCallTarget;
    bool hasSelfDestruct;
    bool hasUnexpectedCreate;
    address[] createAddresses;
    bool hasApprovalDrain;
    address approvalDrainSpender;
    bool hasReentrancy;
    address reentrancyAddress;
    bool hasOwnerSweep;
    uint256 sweepAmount;
    address sweepToken;
}

/// @notice Liquidity-specific economic findings extracted from simulation.
struct LiquidityEconomicFindings {
    bool simulationReverted;
    string revertReason;
    uint256 actualAmountA;
    uint256 actualAmountB;
    uint256 actualLPMinted;
    uint256 expectedLPMinted;
    uint256 lpMintDiscrepancyBps;
    uint256 excessTokenALost;
    uint256 excessTokenBLost;
    uint256 excessValueLostUSD;
    uint256 actualReceivedA;
    uint256 actualReceivedB;
    address pairAddress;
    uint256 lpTotalSupply;
    uint256 reserveA;
    uint256 reserveB;
    bool isFirstDeposit;
    uint256 poolRatio;
    uint256 oracleRatio;
    uint256 ratioDeviationBps;
    bool isRemovalFrozen;
    string removalRevertReason;
    uint256 removalSimAmountA;
    uint256 removalSimAmountB;
    uint256 tokenAPriceUSD;
    uint256 tokenBPriceUSD;
    bool tokenAOracleStale;
    bool tokenBOracleStale;
    uint256 tokenAOracleAge;
    uint256 tokenBOracleAge;
}

/// @notice Full off-chain simulation output for a liquidity operation.
struct LiquidityOffChainResult {
    bool isSafe;
    RiskLevel riskLevel;
    uint256 riskScore;
    LiquidityOpType operation;
    LiquidityTraceFindings trace;
    LiquidityEconomicFindings economic;
    bool routerVerified;
    bool pairVerified;
    bool tokenAVerified;
    bool tokenBVerified;
    uint256 simulatedAt;
    string network;
}
