# Audit Scope

The primary objective of this audit is to identify potential vulnerabilities, logic flaws, and economic exploits within the Preflight Risk Management Protocol.

## In-Scope Contracts
All contracts under the `src/` directory are considered in-scope unless explicitly excluded.

| Directory | Contract | Description |
|-----------|----------|-------------|
| `guards/` | `ERC4626VaultGuard.sol` | Guard for ERC4626 Vault interactions |
| `guards/` | `V2Guards/LiquidityV2Guard.sol` | Guard for Uniswap V2 liquidity additions/removals |
| `guards/` | `V2Guards/SwapV2Guard.sol` | Guard for Uniswap V2 Swaps |
| `guards/` | `lib/TokenGuard.sol` | Core library for validating ERC20 tokens |
| `nftReport/` | `RiskReportNFT.sol` | The ERC721 NFT minting contract |
| `nftReport/` | `SVGRenderer.sol` | On-chain SVG generation engine |
| `preflightRouters/` | `ERC4626Router.sol` | Router for vault risk evaluation |
| `preflightRouters/` | `V2Routers/SwapV2Router.sol` | Router for V2 swaps |
| `preflightRouters/` | `V2Routers/LiquidityV2Router.sol`| Router for V2 liquidity |
| `riskpolicies/` | `ERC4626RiskPolicy.sol` | Policy definition for ERC4626 interactions |
| `riskpolicies/` | `SwapV2RiskPolicy.sol` | Policy definition for swap interactions |
| `riskpolicies/` | `LiquidityV2RiskPolicy.sol` | Policy definition for liquidity interactions |

## Out of Scope
- Foundry Deployment Scripts (`script/` directory).
- Test files and mock contracts (`test/` directory).
- Third-party dependencies (e.g., OpenZeppelin contracts, Uniswap V2 interfaces).
