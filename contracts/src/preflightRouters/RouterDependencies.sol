// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenGuardResult} from "../guards/interfaces/ITokenGuard.sol";
import {LiquidityOpType} from "../types/OffChainTypes.sol";

struct VaultGuardCheckResult {
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

struct SwapV2GuardCheckResult {
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

struct LiquidityV2GuardCheckResult {
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

interface IVaultGuardRouter {
    function checkVault(address vault, uint256 amount, bool isDeposit)
        external
        returns (VaultGuardCheckResult memory result, uint256 previewShares, uint256 previewAssets);

    function storeCheck(address vault, address user, uint256 amount, bool isDeposit)
        external
        returns (VaultGuardCheckResult memory result, uint256 previewShares, uint256 previewAssets);

    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardCheckResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber);
}

interface ISwapV2GuardRouter {
    function swapCheckV2(address router, address[] calldata path, uint256 amountIn)
        external
        returns (SwapV2GuardCheckResult memory result);

    function storeSwapCheck(address router, address[] calldata path, uint256 amountIn, address user)
        external
        returns (SwapV2GuardCheckResult memory result);

    function validateSwapCheck(address router, address[] calldata path, uint256 amountIn, address user)
        external
        view;
}

interface ILiquidityV2GuardRouter {
    function checkLiquidity(
        address user,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOpType operationType
    ) external returns (LiquidityV2GuardCheckResult memory result);

    function storeCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOpType operationType
    ) external returns (LiquidityV2GuardCheckResult memory result);

    function validateCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOpType operationType
    ) external view;
}
