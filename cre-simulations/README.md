<div style="text-align:center" align="center">
    <a href="https://chain.link" target="_blank">
        <img src="https://raw.githubusercontent.com/smartcontractkit/chainlink/develop/docs/logo-chainlink-blue.svg" width="225" alt="Chainlink logo">
    </a>

[![License](https://img.shields.io/badge/license-MIT-blue)](https://github.com/smartcontractkit/cre-templates/blob/main/LICENSE)
[![CRE Home](https://img.shields.io/static/v1?label=CRE\&message=Home\&color=blue)](https://chain.link/chainlink-runtime-environment)
[![CRE Documentation](https://img.shields.io/static/v1?label=CRE\&message=Docs\&color=blue)](https://docs.chain.link/cre)

</div>

## Quick start

### 1) Add the ABI (TypeScript)

Place your ABI under `contracts/abi` as a `.ts` module and export it as `as const`. Then optionally re-export it from `contracts/abi/index.ts` for clean imports.

```ts
// contracts/abi/PriceFeedAggregator.ts
import type { Abi } from 'viem';

export const PriceFeedAggregator = [
  // ... ABI array contents from the contract page ...
] as const;
```

```ts
// contracts/abi/index.ts
export * from './PriceFeedAggregator';
// add more as needed:
// export * from './IERC20';

```

> You can create additional ABI files the same way (e.g., `IERC20.ts`), exporting them as `as const`.

### 2) Configure RPC in `project.yaml`

Add an RPC for the chain you want to read from. For Arbitrum One mainnet:

```yaml
rpcs:
  - chain-name: ethereum-mainnet-arbitrum-1
    url: <YOUR_ARBITRUM_MAINNET_RPC_URL>
```

### 3) Configure the workflow

Create or update `config.json`:

```json
{
  "schedule": "0 */10 * * * *",
  "chainName": "ethereum-mainnet-arbitrum-1",
  "feeds": [
    {
      "name": "BTC/USD",
      "address": "0x6ce185860a4963106506C203335A2910413708e9"
    },
    {
      "name": "ETH/USD",
      "address": "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"
    }
  ]
}
```

* `schedule` uses a 6-field cron expression — this runs every 10 minutes at second 0.
* `chainName` must match the RPC entry in `project.yaml`.
* `feeds` is a list of (name, address) pairs to read.

### 4) Ensure `workflow.yaml` points to your config

```yaml
staging-settings:
  user-workflow:
    workflow-name: "my-workflow"
  workflow-artifacts:
    workflow-path: "."
    config-path: "./config.json"
    secrets-path: ""
```

### 5) Install dependencies

From your project root:

```bash
bun install --cwd ./my-workflow
```

### 6) Run a local simulation

From your project root:

```bash
cre workflow simulate my-workflow
```

You should see output similar to:

```
Workflow compiled
2025-10-30T09:24:27Z [SIMULATION] Simulator Initialized

2025-10-30T09:24:27Z [SIMULATION] Running trigger trigger=cron-trigger@1.0.0
2025-10-30T09:24:28Z [USER LOG] msg="Data feed read" chain=ethereum-mainnet-arbitrum-1 feed=BTC/USD address=0x6ce185860a4963106506C203335A2910413708e9 decimals=8 latestAnswerRaw=10803231994131 latestAnswerScaled=108032.31994131
2025-10-30T09:24:29Z [USER LOG] msg="Data feed read" chain=ethereum-mainnet-arbitrum-1 feed=ETH/USD address=0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612 decimals=8 latestAnswerRaw=378968000000 latestAnswerScaled=3789.68

Workflow Simulation Result:
 "[{\"name\":\"BTC/USD\",\"address\":\"0x6ce185860a4963106506C203335A2910413708e9\",\"decimals\":8,\"latestAnswerRaw\":\"10803231994131\",\"scaled\":\"108032.31994131\"},{\"name\":\"ETH/USD\",\"address\":\"0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612\",\"decimals\":8,\"latestAnswerRaw\":\"378968000000\",\"scaled\":\"3789.68\"}]"
```





# PreFlight — Off-Chain CRE Simulations

Off-chain transaction simulation layer using Chainlink CRE (Compute Runtime Environment).  
Targets **Arbitrum mainnet**, covering Uniswap V2 swaps and ERC4626 vaults.

---

## What this does vs the on-chain guards

| Check | On-Chain Guard | CRE Simulation |
|-------|---------------|----------------|
| TWAP price deviation | ✅ SwapV2Guard | — |
| K-invariant / liquidity | ✅ SwapV2Guard | — |
| Token static properties | ✅ TokenGuard | — |
| Share inflation (preview) | ✅ VaultGuard | — |
| Vault balance mismatch | ✅ VaultGuard | — |
| Fee-on-transfer (heuristic) | ✅ TokenGuard | Actual measurement |
| **DELEGATECALL detection** | — | ✅ Trace analysis |
| **SELFDESTRUCT in path** | — | ✅ Trace analysis |
| **CREATE during execution** | — | ✅ Trace analysis |
| **Owner ERC20 sweep** | — | ✅ Trace (transfer events) |
| **Approval drain** | — | ✅ Trace analysis |
| **Reentrancy detection** | — | ✅ Call stack analysis |
| **Upgrade call in trace** | — | ✅ Trace analysis |
| **Withdrawal freeze** | — | ✅ Redeem simulation |
| **Share price drift** | — | ✅ convertToAssets diff |
| **Chainlink oracle cross-check** | — | ✅ Real market price |
| **Oracle staleness** | — | ✅ updatedAt age |
| **Contract verification** | — | ✅ Arbiscan API |

---

## File structure

```
cre-simulations/
├── my-workflow/
│   ├── simulations/
│   │   ├── shared/
│   │   │   ├── types.ts          ← All result structs + risk weights
│   │   │   ├── chainlink.ts      ← Arbitrum feed addresses + oracle helpers
│   │   │   ├── traceAnalysis.ts  ← DELEGATECALL, sweep, reentrancy, etc.
│   │   │   ├── tokenOverrides.ts ← ERC20 storage slot balance overrides
│   │   │   └── arbiscan.ts       ← Contract verification check
│   │   ├── swapLogic.ts          ← Uniswap V2 swap simulation
│   │   └── vaultLogic.ts         ← ERC4626 vault simulation
│   ├── main.ts                   ← HTTP trigger handler (entry point)
│   ├── package.json
│   └── workflow.yaml             ← CRE workflow definition
├── project.yaml                  ← CRE project definition
├── tsconfig.json
├── .env.example
└── README.md
```

---

## Prerequisites

- Node.js >= 18
- Chainlink CRE CLI: `npm install -g @chainlink/cre-cli`
- An Arbiscan API key (free): https://arbiscan.io/myapikey
- A Chainlink DON account: https://dev.chain.link

---

## Setup

### 1. Install dependencies

```bash
cd cre-simulations
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env and add your ARBISCAN_API_KEY
```

### 3. Type-check the project

```bash
npm run typecheck
```

---

## Running locally (development)

CRE workflows run in a sandboxed DON environment. For local dev you mock
`runtime` and `context`:

```typescript
// local-test.ts
import { onHttpTrigger } from "./my-workflow/main.js";

// Mock runtime with your local RPC
const runtime = {
    capabilities: {
        evm: (network: string) => ({
            call: async (params: any) => { /* use ethers provider */ },
            read: async (params: any) => { /* use ethers provider */ },
        }),
        http: {
            get: async (params: any) => fetch(params.url).then(r => r.json()),
        },
    },
};

// Swap example
const swapContext = {
    data: {
        type:        "SWAP",
        from:        "0xYOUR_WALLET",
        to:          "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24", // Arbitrum Uniswap V2 Router
        data:        "0x...",  // encoded swapExactTokensForTokens calldata
        amountIn:    "1000000000000000000",  // 1 WETH in wei
        amountOutMin:"1900000000",           // min USDC out
        path: [
            "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",  // WETH
            "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",  // USDC.e
        ],
    },
};

const result = await onHttpTrigger(runtime, swapContext);
console.log(JSON.stringify(result, null, 2));
```

---

## Deploying to Chainlink CRE

### 1. Log in

```bash
cre login
```

### 2. Create the project

```bash
cre project create --file project.yaml
```

### 3. Set secrets (API keys)

```bash
cre secrets set ARBISCAN_API_KEY=your_key_here
```

### 4. Deploy the workflow

```bash
cd cre-simulations
cre workflow deploy my-workflow/workflow.yaml --project-id preflight-defi-guard
```

### 5. Get your endpoint URL

```bash
cre workflow status --project-id preflight-defi-guard
# Look for: "httpTrigger URL: https://don-abc123.chain.link/..."
```

---

## Calling the endpoint (from extension/frontend)

### Swap check

```javascript
const result = await fetch("https://don-abc123.chain.link/trigger/preflight", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
        type:        "SWAP",
        from:        userWalletAddress,
        to:          uniswapV2RouterAddress,
        data:        encodedCalldata,         // swapExactTokensForTokens(...)
        amountIn:    amountIn.toString(),
        amountOutMin: amountOutMin.toString(),
        path:        [tokenInAddress, tokenOutAddress],
    }),
});
const report = await result.json();
// report.isSafe, report.riskLevel, report.trace.hasDangerousDelegateCall, etc.
```

### Vault check

```javascript
const result = await fetch("https://don-abc123.chain.link/trigger/preflight", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
        type:         "VAULT",
        from:         userWalletAddress,
        vaultAddress: erc4626VaultAddress,
        amountIn:     amountIn.toString(),
        data:         encodedDepositCalldata,  // deposit(amount, receiver)
        receiver:     userWalletAddress,
    }),
});
const report = await result.json();
// report.isSafe, report.economic.isWithdrawFrozen, report.trace.hasOwnerSweep, etc.
```

---

## Result structure

Both `SwapOffChainResult` and `VaultOffChainResult` share this top-level shape:

```typescript
{
    isSafe:    boolean,     // combined verdict
    riskLevel: "SAFE" | "WARNING" | "CRITICAL",
    riskScore: number,      // 0–100
    trace:     { ... },     // trace-based findings
    economic:  { ... },     // oracle / output findings
    simulatedAt: number,    // unix timestamp
    network:   "arbitrum-mainnet",
}
```

See `shared/types.ts` for the full field-by-field documentation.

---

## Adding a new Chainlink feed

If a token on Arbitrum doesn't have a feed in `chainlink.ts`, add it:

```typescript
// In shared/chainlink.ts
export const ARBITRUM_FEEDS: Record<string, string> = {
    // ... existing feeds ...
    "0xYOUR_TOKEN_ADDRESS_LOWERCASE": "0xCHAINLINK_FEED_ADDRESS",
};
```

Find feed addresses at:  
https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum&page=1















Prerequisites
Node.js ≥ 18 — check with node --version. If you don't have it, install from nodejs.org.
Chainlink CRE CLI — this is the tool that talks to the DON:
bashnpm install -g @chainlink/cre-cli
An Arbiscan API key — free at https://arbiscan.io/myapikey (takes 30 seconds to register).
A Chainlink DON account — go to https://dev.chain.link, sign up, and create a new project. You'll get a project ID and an API key from the dashboard.

Step 1 — Install dependencies
bashcd cre-simulations
npm install
This installs ethers, @chainlink/cre-sdk, and the TypeScript toolchain.

Step 2 — Configure your environment
bashcp .env.example .env
```

Open `.env` and fill in:
```
ARBISCAN_API_KEY=your_key_here
The CRE CLI credentials (CRE_PROJECT_ID, CRE_API_KEY) are managed by the CLI itself after you log in — you don't set them in .env.

Step 3 — Type-check the project
Always run this before deploying. It catches type errors before the DON sees your code:
bashnpm run typecheck
Fix any errors it reports before continuing.

Step 4 — Log in to Chainlink CRE
bashcre login
This opens a browser window. Sign in with your dev.chain.link account. The CLI stores a session token locally.

Step 5 — Register the project
You only do this once per project:
bashcre project create --file project.yaml
```

It will output something like:
```
Project created: preflight-defi-guard (id: proj_abc123...)
Save that project ID — you'll use it in every subsequent command.

Step 6 — Push your API key secret
The DON runtime needs your Arbiscan key but you never hardcode secrets in source files. Push it as a managed secret:
bashcre secrets set ARBISCAN_API_KEY=your_actual_key_here --project-id preflight-defi-guard
The workflow's env block in workflow.yaml already references ARBISCAN_API_KEY by name, so the runtime will inject it automatically.

Step 7 — Deploy the workflow
bashcre workflow deploy my-workflow/workflow.yaml --project-id preflight-defi-guard
```

This bundles your TypeScript, uploads it to the DON, and starts the workflow. On success you'll see:
```
Workflow deployed: preflight-security-simulation
HTTP Trigger URL: https://don-xyz.chain.link/trigger/preflight-security-simulation
Copy that URL. That's your live endpoint. Everything runs on the DON from here — no server of yours is involved.

Step 8 — Verify it's running
bashcre workflow status --project-id preflight-defi-guard
You should see status: RUNNING. If you see status: ERROR, run:
bashcre workflow logs --project-id preflight-defi-guard
That shows the DON's execution logs for your last run.

Step 9 — Call your endpoint
This is how the browser extension (or any frontend) calls the simulation. Here's a curl test for each operation type so you can verify the three branches work before wiring up the extension.
Vault — deposit test:
bashcurl -X POST https://don-xyz.chain.link/trigger/preflight-security-simulation \
  -H "Content-Type: application/json" \
  -d '{
    "type": "VAULT",
    "opType": "DEPOSIT",
    "from": "0xYOUR_WALLET",
    "vaultAddress": "0xSOME_ERC4626_VAULT_ON_ARBITRUM",
    "amount": "1000000000000000000",
    "data": "0x6e553f650000...ENCODED_DEPOSIT_CALLDATA",
    "receiver": "0xYOUR_WALLET"
  }'
Swap — exact tokens in test:
bashcurl -X POST https://don-xyz.chain.link/trigger/preflight-security-simulation \
  -H "Content-Type: application/json" \
  -d '{
    "type": "SWAP",
    "opType": "EXACT_TOKENS_IN",
    "from": "0xYOUR_WALLET",
    "routerAddress": "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
    "data": "0x38ed1739...ENCODED_SWAP_CALLDATA",
    "path": [
      "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
      "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8"
    ],
    "amountIn": "1000000000000000000",
    "amountOutMin": "1900000000",
    "ethValue": "0"
  }'
Liquidity — add test:
bashcurl -X POST https://don-xyz.chain.link/trigger/preflight-security-simulation \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LIQUIDITY",
    "opType": "ADD",
    "from": "0xYOUR_WALLET",
    "routerAddress": "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
    "data": "0xe8e33700...ENCODED_ADD_LIQUIDITY_CALLDATA",
    "tokenA": "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
    "tokenB": "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
    "amountADesired": "1000000000000000000",
    "amountBDesired": "1900000000",
    "amountAMin": "950000000",
    "amountBMin": "1800000000"
  }'
The response will be a full JSON object matching SwapOffChainResult, VaultOffChainResult, or LiquidityOffChainResult — with isSafe, riskLevel, riskScore, and all the breakdown fields.

Step 10 — Wire the extension to the endpoint
In your browser extension, the pre-transaction hook should do this before submitting any tx:
javascriptasync function runPreflightCheck(payload) {
    const SIMULATION_URL = "https://don-xyz.chain.link/trigger/preflight-security-simulation";

    const response = await fetch(SIMULATION_URL, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify(payload),
    });

    const result = await response.json();

    if (result.riskLevel === "CRITICAL" || !result.isSafe) {
        // Block the transaction and show the risk report
        showRiskModal(result);
        return false;
    }

    if (result.riskLevel === "WARNING") {
        // Show warning, let user decide
        const proceed = await askUserToProceed(result);
        return proceed;
    }

    return true; // SAFE — let the transaction through
}
The data field in your payload is the ABI-encoded calldata your extension would normally submit to the wallet. You encode it the same way you would for the actual tx — the simulation uses it to fork-run the exact same call.

Generating the data field
This is the most common point of confusion. The data you pass to the simulation is the same calldata you'd send in the real transaction. You build it with ethers the same way:
javascript// Swap example
const routerIface = new ethers.utils.Interface([
    "function swapExactTokensForTokens(uint256,uint256,address[],address,uint256) returns (uint256[])"
]);
const calldata = routerIface.encodeFunctionData("swapExactTokensForTokens", [
    amountIn,
    amountOutMin,
    path,
    userAddress,
    deadline
]);

// Then pass it:
payload.data = calldata;
payload.opType = "EXACT_TOKENS_IN";
javascript// Vault deposit example
const vaultIface = new ethers.utils.Interface([
    "function deposit(uint256,address) returns (uint256)"
]);
const calldata = vaultIface.encodeFunctionData("deposit", [assets, receiver]);

payload.data = calldata;
payload.opType = "DEPOSIT";

Updating the deployment
When you change simulation code, redeploy with:
bashcre workflow deploy my-workflow/workflow.yaml --project-id preflight-defi-guard
The DON hot-swaps to the new version. No downtime, no new URL.

Monitoring
bash# See last N executions with their inputs/outputs
cre workflow logs --project-id preflight-defi-guard --tail 20

# Check current status and resource usage
cre workflow status --project-id preflight-defi-guard

Common errors and fixes
UNTRUSTED_DEX_ROUTER — The router address you passed isn't in the on-chain guard's trusted list. Either add it with swapGuard.setTrustedRouter(addr, true) or verify you're using the correct Arbitrum router address (0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24 for Camelot V2, 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506 for SushiSwap on Arbitrum).
SIMULATION_EXCEPTION — The CRE evm.call itself threw. Most common cause: malformed data field (wrong ABI encoding). Double-check that your calldata matches the function signature exactly.
NO_CHECK_STORED — You called the execute phase before the store phase in the on-chain router. The off-chain simulation is separate — this error comes from the on-chain PreFlightRouter, not the CRE workflow.
Timeout errors — The DON has a 30 second limit (set in workflow.yaml). The verification step (3 Arbiscan calls) adds ~3s per contract. If you're consistently hitting the limit, you can cache verification results client-side — verified contracts don't change.
Storage slot override silent failure — If INSUFFICIENT_BALANCE doesn't appear but your simulation shows the user had no tokens, the token uses a non-standard storage layout (e.g. namespaced proxy storage). In that case the override silently fails and the simulation runs with the user's real on-chain balance. This is safe — it just means the simulation is less forgiving, not wrong.


