
# PreFlight — the Zero-Trust DeFi Firewall for Arbitrum

---

## 1) Project description 

**Name:** PreFlight — the Zero-Trust DeFi Firewall for Arbitrum  

**What it is:**  
A protocol-aware, transaction-level security gateway that runs deterministic, auditable on-chain checks (Guards) and deeper off-chain transaction simulations to detect exploitation patterns before a user’s transaction is executed.

**What it does:**  
For four user actions — swap, add liquidity, remove liquidity, and vault deposit/withdraw — PreFlight performs multi-signal verification and either  
(a) reverts malicious/very high-confidence transactions on-chain, or  
(b) provides a detailed risk report and “do you still want to proceed?” UX for ambiguous cases.

**Problem it solves:**  
Pre-transaction, real-time protection from flash-loan manipulation, donation/inflation attacks, token-mint/ownership rug pulls, tax/fee tokens, reentrancy/hidden drains, MEV sandwich and liquidity JIT attacks — all of which are not captured by standard price previews and slippage warnings.

---

## 2) How it works — end-to-end

### High level flow

#### 1. User intent (UI / extension / dApp)
- User prepares an action (swap / add / remove / deposit / withdraw).
- Wallet signs a meta intent or the UI routes through ArbSentinelRouter.

#### 2. Pre-check: on-chain Guards (fast & deterministic)
- Router calls relevant view functions in Guard contracts (SwapGuard, LiquidityGuard, VaultGuard).
- These run cheap checks against on-chain state:
  - reserves  
  - TWAP  
  - owner flags  
  - totalAssets / totalSupply  
  - token metadata  
  - EOA vs contract  
  - verification status  

#### 3. Decision branch
- If on-chain checks indicate **HIGH RISK** (high-confidence patterns):  
  - revert the transaction immediately (Router reverts).
- Else if medium / ambiguous risk:  
  - continue to off-chain simulation.
- Else:  
  - pass and proceed to execution adapter (direct call to protocol).

#### 4. Deep X-Ray Off-chain Simulation (fork + trace)
- Off-chain service (your backend) forks chain state at the current block.
- Performs eth_call or Tenderly-style simulation of the transaction.
- Inspects the execution trace and guard heuristics.
- Produces an interpretable reason stack and numeric safety score (0–100).

#### 5. Final UX
- UI shows:
  - Safety Score  
  - human readable reasons  
  - a minimal reproduction script  
  - options: Cancel / Proceed (with explicit confirmation)
- For passes, the router executes the action.
- For high-risk cases, the router prevents it.

### Why this beats price previews & slippage
- Price preview only computes expected token output given current state — it cannot detect *why* a preview is correct.
- PreFlight uses state, oracle history (TWAP), contract code signals, ownership and mintability checks, and an execution trace.
- Slippage settings are static and cannot stop malicious internal transfers, taxes, or delegatecalls hidden in the router.

### Important design notes
- On-chain Guards must be view-only and gas-cheap.
- Heavy heuristics and fork-based trace analysis live off-chain.
- Use a conservative “2-of-3” confirmation before reverting on uncertain signals.

---

## 3) Exhaustive checks — by module / file

Below is a single canonical list of checks. Implement these as on-chain view functions and corresponding off-chain checkers that run on the forked trace.  
Each check is labeled as on-chain, off-chain simulation, or trace.

NOTE: thresholds are provided as sensible defaults. Tune these with production dataset.

---

## Cross-cutting checks (applies to all actions)

- **Canonical contract verification**
  - On-chain: check address against trusted registry (on-chain or backend whitelist).
  - Off-chain: check verification status, compiler version, source, and creation transaction.

- **Unverified contract flag**
  - Off-chain: raise high risk for unverified code.

- **Delegatecall / callcode usage**
  - Trace: DELEGATECALL invoked with unknown target → HIGH RISK.

- **SelfDestruct in call path**
  - Trace: SELFDESTRUCT observed → HIGH RISK.

- **tx.origin usage**
  - Static analysis via trace or verified source.

- **Third-party transfer of user funds**
  - Trace: internal transfer to address not equal to router or expected destination → HIGH RISK.

- **Ownership or admin hooks during action**
  - Trace / on-chain: ownership-only function called → HIGH RISK.

- **Token decimal mismatch & rounding**
  - On-chain decimal sanity check.
  - Off-chain rounding loss simulation.

- **Fee-on-transfer or tax tokens**
  - Off-chain: simulate transfer and compare received amount.

- **Reentrancy pattern**
  - Trace: repeated balance modification mid-flow.

- **Mintable or pausable token**
  - On-chain: inspect ABI for mint, pause, blacklist functions.

- **Token age**
  - Off-chain: age < 7 days → warning.

- **Ownership concentration**
  - Off-chain: top holders exceed threshold → elevated risk.

- **New LP pair**
  - On-chain: pair created < 1000 blocks → warning.

- **Minimal liquidity**
  - On-chain: TVL < $50k → high risk for large trades.

---

## Module: SwapGuard (swap)

**Files:**  
guards/SwapGuard.sol  
adapters/UniswapAdapter.sol  
backend/swapChecks.js  

### On-chain view checks
1. isCanonicalRouter(address router)
2. spotVsTwap(poolAddr, window)
   - Stable pools: >0.5% warning, >1% block
   - Major pools: >2% warning, >5% block
   - Low TVL: >1% warning
3. reserveDeltaSinceLastBlock(poolAddr)
4. minLiquidityCheck(poolAddr, expectedAmount)
5. tokenHasMintOrOwner(token)
6. tokenDecimalsCheck(token)
7. isStablePair(poolAddr)

### Off-chain simulation & trace checks
8. Simulated vs quoted output comparison
9. Delegatecall or unknown call detection
10. Tax / fee detection
11. Third-party transfer detection
12. Sandwich & MEV heuristic
13. Slippage anomaly detection

---

## Module: LiquidityGuards (add / remove liquidity)

**Files:**  
guards/LiquidityGuard.sol  
adapters/AMMAdapter.sol  
backend/liquidityChecks.js  

### Add Liquidity — on-chain
1. tokenMintableCheck
2. tokenOwnershipConcentration
3. tokenAge
4. pairCreationAge
5. isRouterCanonical
6. approvalFlowCheck
7. mintEventInBlock

### Add Liquidity — off-chain / trace
8. Simulate add-liquidity correctness
9. New token transfer hook trap
10. Hidden taxes & fees

### Remove Liquidity — on-chain
11. lpShareOwnershipCheck
12. withdrawalImpactEstimate

### Remove Liquidity — off-chain / trace
13. Simulate withdrawal correctness
14. External arbitrary call detection

---

## Module: VaultGuards (deposit / withdraw) — ERC-4626 focus

**Files:**  
guards/VaultGuard.sol  
adapters/ERC4626Adapter.sol  
backend/vaultChecks.js  

### Core on-chain checks
1. exchangeRateCheck
2. assetsBalanceMismatch
3. totalAssetsJumpDetect
4. isVaultVerified
5. vaultCallsExternalAdminOnDepositWithdraw
6. withdrawAllPathSafety

### Off-chain simulation & trace checks
7. Simulate deposit share correctness
8. Simulate withdraw asset correctness
9. Liquidity mismatch replay
10. Reentrancy pattern

---

## Module: ArbSentinelRouter (orchestrator)

**Files:**  
contracts/ArbSentinelRouter.sol  

### Responsibilities
1. Accept signed user intent or direct call
2. Invoke Guard checks and revert on fail_high
3. Handle fail_medium via off-chain simulation or UI override
4. Expose view functions for UIs
5. Emit risk snapshot events

---

## Module: Registry & Policy

**Files:**  
contracts/ProtocolRegistry.sol  
contracts/Policy.sol  

1. Canonical registry of routers, vaults, AMMs
2. Policy contract for thresholds
3. Event logs for reports and decisions

---

## Module: On-chain Evidence & NFT Minter

**Files:**  
contracts/RiskReportNFT.sol  
contracts/ReportRegistry.sol  

1. Mint proof NFT with IPFS CID
2. Store on-chain hash of report
3. Support SBT and transferable badges
4. Require explicit user consent


---

### Frontend 

**Goals:** present the exact security state and let user choose to proceed.

**Core pages / widgets**
- Dashboard with quick scan
- Action flow with preflight checks
- Detailed report page
- Settings
- Developer / judge view

**UX elements**
- Clear green / amber / red states
- Explicit override path
- Transparent blocking reasons

**Wallet integration**
- MetaMask and WalletConnect
- Client-mode and Router-mode
- Simplified buildathon flow

---

## Browser extension (optional, high-impact)

**Purpose:** intercept non-trusted router calls.

**Design**
- Inject content script
- Query PreFlight checks
- Modal overlay with Safety Score

**Tradeoffs**
- High impact
- Increased build complexity

---

## Backend (Node.js / TypeScript recommended)

### Services
1. Simulation service
2. Registry & policy service
3. Report store
4. NFT minting service
5. Analytics & telemetry
6. Worker & queue

**Datastore**
- Postgres for metadata
- IPFS or Arweave for reports

---

## 5) Risk report & NFT design

### Two NFT variants

1. **SBT Report (Soulbound)**  
   Non-transferable proof of transaction scan and safety report.

2. **Badge NFT (Transferable)**  
   Incentive badge for positive contribution.

### Why both
- SBT for security reputation and trust
- Badges for adoption and marketing
