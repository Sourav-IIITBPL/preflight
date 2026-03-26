// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    VaultGuardResult,
    SwapV2GuardResult,
    LiquidityV2GuardResult,
    LiquidityOperationType
} from "../../types/OnChainTypes.sol";

interface IERC4626VaultGuard {
    function checkVault(address vault, uint256 amount, bool isDeposit)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets);

    function storeCheck(address vault, address user, uint256 amount, bool isDeposit)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets);

    function validate(address vault, address user, uint256 amount, bool isDeposit) external view;

    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber);
}

interface ISwapV2Guard {
    function swapCheckV2(address router, address[] calldata path, uint256 amountIn)
        external
        returns (SwapV2GuardResult memory result);

    function storeSwapCheck(address router, address[] calldata path, uint256 amountIn, address user)
        external
        returns (SwapV2GuardResult memory);

    function validateSwapCheck(address router, address[] calldata path, uint256 amountIn, address user) external view;
}

interface ILiquidityV2Guard {
    function checkLiquidity(
        address user,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOperationType operationType
    ) external returns (LiquidityV2GuardResult memory result);

    function storeCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOperationType operationType
    ) external returns (LiquidityV2GuardResult memory result);

    function validateCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOperationType operationType
    ) external view;
}
