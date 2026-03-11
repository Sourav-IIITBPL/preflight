# PreFlight Frontend

## What
PreFlight frontend is the user-facing security layer for Arbitrum DeFi transactions.
It sits before execution and guides users through:
1. transaction intent capture,
2. off-chain CRE simulation,
3. on-chain guard evaluation,
4. risk report review,
5. report NFT mint,
6. guarded execution through `PreFlightRouter`.

## Why
DEX previews are helpful but often incomplete for security-critical decisions.
PreFlight adds a structured verification step before signing and execution so users can inspect risk evidence first.

## When
PreFlight should run **after user sets swap/liquidity/vault parameters** and **before wallet signature/execution**.

## How (System View)
1. User activates floating PreFlight launcher.
2. User opens sidebar only when ready.
3. PreFlight captures/accepts intent fields.
4. PreFlight runs off-chain CRE simulation.
5. PreFlight runs on-chain guard checks.
6. Frontend aggregates results into one risk report.
7. User reviews report (freshness window: 20s).
8. User mints RiskReport NFT.
9. User executes via `PreFlightRouter`.

## Workflow (User Interaction)
1. User fills swap parameters on DEX.
2. User clicks DEX swap/preview flow.
3. DEX builds transaction calldata.
4. PreFlight intercepts/receives transaction intent.
5. PreFlight decodes calldata and extracts parameters.
6. User clicks **Check PreFlight**.
7. PreFlight sends payload to CRE (off-chain checks) + runs on-chain checks.
8. Risk report is generated and shown to user.
9. If report stays open for more than 20s, checks re-run automatically.
10. User mints RiskReport NFT.
11. User clicks execute swap via PreFlightRouter.
12. User receives wallet signature request.
13. PreFlightRouter executes against DEX router/liquidity pools.

## Data Captured / Used
Core fields used by simulation and checks:
1. `type` and `opType`
2. `from` (wallet)
3. `chainId/network`
4. `routerAddress` or `vaultAddress`
5. `data` (tx calldata)
6. route/path and amount fields (`amountIn`, `amountOutMin`, etc.)
7. `ethValue`

## Current Frontend Scope (`src1`)
1. Landing page remains visible after launcher activation.
2. Floating icon appears after launch and opens sidebar on click.
3. Sidebar runs checks only on explicit **Check PreFlight** click.
4. CRE payload wiring is implemented (`VITE_PREFLIGHT_SIM_URL`).
5. Report freshness auto-recheck is set to 20 seconds.
6. Mint + execute flow is wired in UI state.

## Constraint You Should Know
A normal website tab cannot read arbitrary external tab/window internals directly.
For full live DEX interception across websites (Camelot tab, etc.), production architecture requires a browser extension runtime (content script + page injection + message bridge).

## Environment Variables
Create `.env` in `frontend/`:

```bash
VITE_PREFLIGHT_SIM_URL=<your_CRE_http_trigger_url>
# Optional: default is cre
VITE_PREFLIGHT_SIM_FORMAT=cre
VITE_PREFLIGHT_ROUTER_ADDRESS=<optional_router_contract>
VITE_PREFLIGHT_REPORT_NFT_ADDRESS=<optional_nft_contract>
```

## Run Locally
Default app:

```bash
cd frontend
npm install
npm run dev
```

Run `src1` entry (without replacing `src`):

```bash
cd frontend
npm run dev -- --config .vite-src1.config.mjs
```

## Code Structure (Implemented)
```text
frontend/src1/
  app/
  pages/
  features/
    launchpad/
    preflight-session/
    reports/
    portfolio/
  services/
    api/
    chain/
    adapters/
  shared/
  styles/
```
