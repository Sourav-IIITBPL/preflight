// ============================================================================
//  types.ts — Result structs for all off-chain CRE simulations
//
//  Vault  : DEPOSIT | MINT | WITHDRAW | REDEEM
//  Swap   : EXACT_TOKENS_IN | EXACT_TOKENS_OUT | EXACT_ETH_IN | EXACT_ETH_OUT
//           EXACT_TOKENS_FOR_ETH | TOKENS_FOR_EXACT_ETH
//  Liquid : ADD | ADD_ETH | REMOVE | REMOVE_ETH
//
//  ON-CHAIN guards handle          OFF-CHAIN CRE uniquely adds
//  ──────────────────────────────  ─────────────────────────────────────────
//  TWAP deviation                  Execution trace DELEGATECALL target
//  K-invariant / liquidity         Execution trace SELFDESTRUCT
//  Token static properties         Execution trace CREATE / CREATE2
//  Share inflation preview         Owner ERC20 sweep via trace
//  Vault balance mismatch          Approval drain (unknown spender)
//  Fee-on-transfer heuristics      Actual fee via balance delta
//  ERC4626 preview mismatch        Reentrancy in call stack
//                                  upgradeTo() mid-execution
//                                  Chainlink oracle cross-check (not TWAP)
//                                  Oracle staleness
//                                  Vault: exit freeze (honeypot sim)
//                                  Vault: share price drift pre/post op
//                                  Vault: asset over-pull on mint()
//                                  LP: pool ratio vs fair Chainlink ratio
//                                  LP: first-depositor attack detection
//                                  LP: add→remove freeze (LP honeypot)
//                                  LP: excess token loss from ratio mismatch
// ============================================================================

export type VaultOpType     = "DEPOSIT" | "MINT" | "WITHDRAW" | "REDEEM";
export type SwapOpType      = "EXACT_TOKENS_IN" | "EXACT_TOKENS_OUT" | "EXACT_ETH_IN" | "EXACT_ETH_OUT" | "EXACT_TOKENS_FOR_ETH" | "TOKENS_FOR_EXACT_ETH";
export type LiquidityOpType = "ADD" | "ADD_ETH" | "REMOVE" | "REMOVE_ETH";
export type RiskLevel       = "SAFE" | "WARNING" | "CRITICAL";

// ─── callTracer entry

export interface TraceEntry {
    type:     "CALL" | "DELEGATECALL" | "STATICCALL" | "CREATE" | "CREATE2" | "SELFDESTRUCT";
    from:     string;
    to?:      string;
    value?:   string;
    input?:   string;
    output?:  string;
    gas?:     string;
    gasUsed?: string;
    error?:   string;
    calls?:   TraceEntry[];
}

// ─── Shared trace findings ────────────────────────────────────────────────────

export interface SharedTraceFindings {
    hasDangerousDelegateCall: boolean;
    delegateCallTarget:       string | null;
    hasSelfDestruct:          boolean;
    hasUnexpectedCreate:      boolean;
    createAddresses:          string[];
    hasApprovalDrain:         boolean;
    approvalDrainSpender:     string | null;
    hasReentrancy:            boolean;
    reentrancyAddress:        string | null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  VAULT
// ─────────────────────────────────────────────────────────────────────────────

export interface VaultTraceFindings extends SharedTraceFindings {
    hasOwnerSweep:  boolean;
    sweepAmount:    string;
    sweepToken:     string | null;
    hasUpgradeCall: boolean;
    upgradeTarget:  string | null;
}

export interface VaultEconomicFindings {
    simulationReverted: boolean;
    revertReason:       string;

    /**
     * Primary output per operation:
     *   deposit  → shares minted
     *   mint     → assets consumed (what the vault pulled from user)
     *   withdraw → shares burned
     *   redeem   → assets received
     */
    primaryOutput:        string;
    primaryExpected:      string;   // from preview* function
    outputDiscrepancyBps: number;   // flag if > 100 BPS (1%)

    // Share price drift — deposit and mint only
    sharePriceBefore:    string;    // convertToAssets(1e18) before op
    sharePriceAfter:     string;    // convertToAssets(1e18) after op
    sharePriceDriftBps:  number;

    // Exit honeypot check — deposit → redeem sim / mint → redeem sim
    isExitFrozen:      boolean;
    exitRevertReason:  string;
    exitSimulatedOut:  string;   // assets the exit sim would return

    // mint() specific: how many assets were actually pulled vs previewMint
    actualAssetPull: string;
    excessPullBps:   number;    // (pull - previewMint) / previewMint × 10000

    // Oracle
    assetPriceUSD:    string;
    assetOracleStale: boolean;
    assetOracleAge:   number;
}

export interface VaultOffChainResult {
    isSafe:    boolean;
    riskLevel: RiskLevel;
    riskScore: number;
    operation: VaultOpType;
    trace:     VaultTraceFindings;
    economic:  VaultEconomicFindings;
    vaultVerified: boolean;
    assetVerified: boolean;
    simulatedAt:   number;
    network:       string;
}

// ─────────────────────────────────────────────────────────────────────────────
//  SWAP
// ─────────────────────────────────────────────────────────────────────────────

export interface SwapTraceFindings extends SharedTraceFindings {}

export interface SwapEconomicFindings {
    simulationReverted: boolean;
    revertReason:       string;

    // Actual consumed input and received output (both in token wei)
    actualAmountIn:  string;
    actualAmountOut: string;

    // exactOut only: (amountInMax - actualAmountIn) / amountInMax × 10000
    inputHeadroomBps: number;

    // ETH-out swaps: excess ETH returned to user
    ethRefunded: string;

    // Chainlink cross-check
    oracleFairAmountOut: string;
    priceImpactBps:      number;
    oracleDeviation:     boolean;

    // Actual fee measurement
    isFeeOnTransfer:    boolean;
    measuredFeePercent: number;

    // Oracle health
    tokenInPriceUSD:     string;
    tokenOutPriceUSD:    string;
    tokenInOracleStale:  boolean;
    tokenOutOracleStale: boolean;
    tokenInOracleAge:    number;
    tokenOutOracleAge:   number;
}

export interface SwapOffChainResult {
    isSafe:    boolean;
    riskLevel: RiskLevel;
    riskScore: number;
    operation: SwapOpType;
    trace:     SwapTraceFindings;
    economic:  SwapEconomicFindings;
    routerVerified:   boolean;
    tokenInVerified:  boolean;
    tokenOutVerified: boolean;
    simulatedAt: number;
    network:     string;
}

// ─────────────────────────────────────────────────────────────────────────────
//  LIQUIDITY
// ─────────────────────────────────────────────────────────────────────────────

export interface LiquidityTraceFindings extends SharedTraceFindings {
    hasOwnerSweep: boolean;
    sweepAmount:   string;
    sweepToken:    string | null;
}

export interface LiquidityEconomicFindings {
    simulationReverted: boolean;
    revertReason:       string;

    // Add results
    actualAmountA:        string;
    actualAmountB:        string;
    actualLPMinted:       string;
    expectedLPMinted:     string;   // formula: min(a/rA, b/rB) × totalSupply
    lpMintDiscrepancyBps: number;

    // Excess token loss: tokens above optimal ratio are donated to pool
    excessTokenALost:   string;
    excessTokenBLost:   string;
    excessValueLostUSD: string;   // 1e18 scaled

    // Remove results
    actualReceivedA: string;
    actualReceivedB: string;

    // Pool state at simulation time
    pairAddress:   string;
    lpTotalSupply: string;
    reserveA:      string;
    reserveB:      string;
    isFirstDeposit: boolean;   // totalSupply == 0 → first-depositor attack risk

    // Pool ratio vs Chainlink fair ratio (pool manipulation detection)
    poolRatio:         string;   // reserveB/reserveA × 1e18
    oracleRatio:       string;   // tokenAPriceUSD/tokenBPriceUSD × 1e18
    ratioDeviationBps: number;

    // LP honeypot check — add → remove sim
    isRemovalFrozen:     boolean;
    removalRevertReason: string;
    removalSimAmountA:   string;
    removalSimAmountB:   string;

    // Oracle
    tokenAPriceUSD:    string;
    tokenBPriceUSD:    string;
    tokenAOracleStale: boolean;
    tokenBOracleStale: boolean;
    tokenAOracleAge:   number;
    tokenBOracleAge:   number;
}

export interface LiquidityOffChainResult {
    isSafe:    boolean;
    riskLevel: RiskLevel;
    riskScore: number;
    operation: LiquidityOpType;
    trace:     LiquidityTraceFindings;
    economic:  LiquidityEconomicFindings;
    routerVerified: boolean;
    pairVerified:   boolean;
    tokenAVerified: boolean;
    tokenBVerified: boolean;
    simulatedAt: number;
    network:     string;
}

// ─── ABI selectors ────────────────────────────────────────────────────────────

export const SELECTORS = {
    TRANSFER:           "0xa9059cbb",
    TRANSFER_FROM:      "0x23b872dd",
    APPROVE:            "0x095ea7b3",
    INCREASE_ALLOWANCE: "0x39509351",

    DEPOSIT_VAULT:      "0x6e553f65",
    MINT_VAULT:         "0x94bf804d",
    WITHDRAW_VAULT:     "0xb460af94",
    REDEEM_VAULT:       "0xba087652",

    SWAP_EXACT_TOKENS_FOR_TOKENS:     "0x38ed1739",
    SWAP_TOKENS_FOR_EXACT_TOKENS:     "0x8803dbee",
    SWAP_EXACT_ETH_FOR_TOKENS:        "0x7ff36ab5",
    SWAP_ETH_FOR_EXACT_TOKENS:        "0xfb3bdb41",
    SWAP_EXACT_TOKENS_FOR_ETH:        "0x18cbafe5",
    SWAP_TOKENS_FOR_EXACT_ETH:        "0x4a25d94a",
    SWAP_EXACT_TOKENS_FOR_TOKENS_FOT: "0x5c11d795",
    SWAP_EXACT_ETH_FOR_TOKENS_FOT:    "0xb6f9de95",

    ADD_LIQUIDITY:        "0xe8e33700",
    ADD_LIQUIDITY_ETH:    "0xf305d719",
    REMOVE_LIQUIDITY:     "0xbaa2abde",
    REMOVE_LIQUIDITY_ETH: "0x02751cec",

    UPGRADE_TO:          "0x3659cfe6",
    UPGRADE_TO_AND_CALL: "0x4f1ef286",
} as const;

// ─── Risk weights and thresholds ─────────────────────────────────────────────

export const RISK_WEIGHTS = {
    DANGEROUS_DELEGATECALL:  100,
    SELFDESTRUCT:            100,
    OWNER_SWEEP:             100,
    APPROVAL_DRAIN:          100,
    UPGRADE_CALL:             90,
    EXIT_FROZEN:              90,
    LP_REMOVAL_FROZEN:        90,
    SIMULATION_REVERT:        80,
    FIRST_DEPOSIT:            75,
    REENTRANCY:               70,
    UNEXPECTED_CREATE:        60,
    EXCESS_PULL:              60,
    ORACLE_DEVIATION:         50,
    HIGH_OUTPUT_DISCREPANCY:  50,
    RATIO_DEVIATION:          50,
    SHARE_PRICE_DRIFT:        40,
    FEE_ON_TRANSFER:          30,
    ORACLE_STALE:             30,
    CONTRACT_UNVERIFIED:      20,
} as const;

export const THRESHOLDS = {
    PRICE_IMPACT_WARN_BPS:        500,
    PRICE_IMPACT_CRITICAL_BPS:    1000,
    SHARE_DISCREPANCY_WARN_BPS:   100,
    SHARE_PRICE_DRIFT_WARN_BPS:   50,
    EXCESS_PULL_WARN_BPS:         10,
    FEE_ON_TRANSFER_MIN_BPS:      10,
    RATIO_DEVIATION_WARN_BPS:     500,
    RATIO_DEVIATION_CRITICAL_BPS: 1000,
    LP_MINT_DISCREPANCY_WARN_BPS: 100,
    MAX_ORACLE_AGE_SECONDS:       3600,
} as const;