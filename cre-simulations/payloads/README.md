# Local Simulation Payloads

This folder is organized by logic module and includes **all supported operation types**:

- `swap/` -> 6 payloads for `swapLogic.ts`
- `liquidity/` -> 4 payloads for `liquidityLogic.ts`
- `vault/` -> 4 payloads for `vaultLogic.ts`

## Run a single payload

From project root:

```bash
cre workflow simulate ./my-workflow --non-interactive --trigger-index 0 --http-payload @payloads/swap/01-exact-tokens-in.json
```

## Run all payloads

```bash
bash payloads/run-all.sh
```

## Important notes

- Swap and liquidity payloads are pre-filled for Arbitrum WETH/USDC.e and Sushi V2 router `0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506`.
- Vault payloads are templates. Replace `vaultAddress` in each `vault/*.template.json` with a real Arbitrum ERC4626 vault before running.
- If you edit token/amount/path fields, re-encode `data` to match the same function arguments exactly.
