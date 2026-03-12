# PreFlight Frontend

## What
PreFlight frontend is a security-first transaction execution interface.
Users perform DEX actions inside PreFlight, not directly on external DEX tabs.
Current DEX targets:
1. Camelot (Arbitrum)
2. SaucerSwap (Hedera)

## Why
PreFlight inserts a security checkpoint between "user action" and "wallet signature".
It gives users a risk verdict before execution, with off-chain CRE simulation + on-chain checks.

## When
Use PreFlight at the moment the user initiates swap/liquidity/vault actions and before signing.

## How (Product Flow)
1. User lands on Home page.
2. User clicks Launch.
3. Mid-sized modal appears: "Choose your DEX".
4. User selects Camelot or SaucerSwap.
5. Modal closes.
6. DEX page becomes active (also visible in nav as `DEX`).
7. DEX website is embedded inside PreFlight runtime page with URL bar on top.
8. User interacts with DEX normally (swap/add/remove liquidity/etc).
9. Transaction intent is intercepted and calldata/parameters are captured.
10. PreFlight sidebar opens and runs checks chronologically.
11. Large centered report modal appears with verdict.
12. If report is stale (>10s view time), checks re-run.
13. User mints RiskReport NFT.
14. User executes through PreFlightRouter.
15. Wallet signature prompt appears.
16. PreFlightRouter executes on target DEX router/pools.
17. Success popup is shown and auto-closes.

## Workflow Stages (Sidebar Timeline)
1. Intercept transaction intent
2. Decode calldata + parameters
3. Off-chain CRE simulation
4. On-chain guard checks
5. Risk report generation

## User Interactions
1. Launch button on Home
2. DEX selection modal choice
3. DEX runtime operations inside embedded DEX page
4. Floating PreFlight icon (bottom-right on DEX page)
5. Sidebar review + check run
6. Report review + mint
7. Execute transaction button

## Runtime Rules
1. Floating icon is visible on DEX page.
2. Floating icon is clickable only after minimum intent fields are present.
3. Sidebar is opened from icon click (or auto-open on intercepted calldata update).
4. Success toast auto-clears in 3 seconds.

## Off-chain CRE Wiring
`src1` sends CRE-compatible payloads from frontend intent data.
Set:

```bash
VITE_PREFLIGHT_SIM_URL=<CRE trigger URL>
VITE_PREFLIGHT_SIM_FORMAT=cre
```

Payload fields include:
1. `type`, `opType`
2. `from`
3. `routerAddress` or `vaultAddress`
4. `data` (calldata)
5. amount/path fields by operation type

## Important Constraint
Full automatic interception from real third-party DEX pages across browser contexts requires extension runtime (content script + injected page hook).
Current `src1` is prepared for this model and supports local runtime flow in the integrated DEX page.

## Local Run
Default frontend:

```bash
cd frontend
npm install
npm run dev
```

Run `src1` entry without replacing `src`:

```bash
cd frontend
npm run dev -- --config .vite-src1.config.mjs
```
