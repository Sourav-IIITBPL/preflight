// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    VaultGuardResult,
    SwapV2GuardResult,
    LiquidityV2GuardResult,
    LiquidityOperationType
} from "../../types/OnChainTypes.sol";
import {VaultOpType} from "../../types/OffChainTypes.sol";

/**
 * @author Sourav-IITBPL
 * @notice Interface for ERC-4626 vault guard checks and stored validations.
 */
interface IERC4626VaultGuard {
    /**
     * @notice Runs a vault safety check for an ERC-4626 operation.
     * @param vault Address of the vault to inspect.
     * @param amount Assets or shares to evaluate.
     * @param opType Type of ERC-4626 operation being evaluated.
     * @return result Guard result for the requested operation.
     * @return previewShares Previewed shares from the guard.
     * @return previewAssets Previewed assets from the guard.
     */
    function checkVault(address vault, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets);

    /**
     * @notice Stores a vault check for later validation.
     * @param vault Address of the vault to inspect.
     * @param user Address whose check is being stored.
     * @param amount Assets or shares to evaluate.
     * @param opType Type of ERC-4626 operation being evaluated.
     * @return result Guard result for the requested operation.
     * @return previewShares Previewed shares from the guard.
     * @return previewAssets Previewed assets from the guard.
     */
    function storeCheck(address vault, address user, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets);

    /**
     * @notice Validates the latest stored vault check for a user.
     * @param vault Address of the vault to validate.
     * @param user Address whose stored check is validated.
     * @param amount Assets or shares to validate.
     * @param opType Type of ERC-4626 operation being validated.
     */
    function validate(address vault, address user, uint256 amount, VaultOpType opType) external view;

    /**
     * @notice Returns the latest stored vault check for a user.
     * @param vault Address of the vault used in the stored check.
     * @param user Address whose stored check is requested.
     * @return result Stored guard result.
     * @return previewShares Stored previewed shares.
     * @return previewAssets Stored previewed assets.
     * @return blockNumber Block number when the check was stored.
     */
    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber);
}

/**
 * @author Sourav-IITBPL
 * @notice Interface for guarded Uniswap V2-style swap checks and validations.
 */
interface ISwapV2Guard {
    /**
     * @notice Runs a swap guard check for the provided path and amount.
     * @param router Address of the AMM router.
     * @param path Swap path to evaluate.
     * @param amount Amount used for the check.
     * @param isExactTokenIn Whether the amount represents an exact-input swap.
     * @return result Guard result for the requested swap.
     */
    function swapCheckV2(address router, address[] calldata path, uint256 amount, bool isExactTokenIn)
        external
        returns (SwapV2GuardResult memory result, uint256[] memory amountsOut);

    /**
     * @notice Stores a swap guard check for later validation.
     * @param router Address of the AMM router.
     * @param path Swap path to evaluate.
     * @param amount Amount used for the check.
     * @param isExactTokenIn Whether the amount represents an exact-input swap.
     * @param user Address whose check is being stored.
     * @return Stored guard result.
     */
    function storeSwapCheck(address router, address[] calldata path, uint256 amount, bool isExactTokenIn, address user)
        external
        returns (SwapV2GuardResult memory);

    /**
     * @notice Validates the latest stored swap check for a user.
     * @param router Address of the AMM router.
     * @param path Swap path to validate.
     * @param amount Amount used for the check.
     * @param isExactTokenIn Whether the amount represents an exact-input swap.
     * @param user Address whose stored check is validated.
     */
    function validateSwapCheck(
        address router,
        address[] calldata path,
        uint256 amount,
        bool isExactTokenIn,
        address user
    ) external;
}

/**
 * @author Sourav-IITBPL
 * @notice Interface for guarded Uniswap V2-style liquidity checks and validations.
 */
interface ILiquidityV2Guard {
    /**
     * @notice Runs a liquidity guard check for the requested operation.
     * @param user Address performing the operation.
     * @param router Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B or zero address for ETH flows.
     * @param amountADesired Desired amount associated with token A or LP amount.
     * @param amountBDesired Desired amount associated with token B.
     * @param operationType Liquidity operation being checked.
     * @return result Guard result for the requested liquidity action.
     */
    function checkLiquidity(
        address user,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOperationType operationType
    ) external returns (LiquidityV2GuardResult memory result);

    /**
     * @notice Stores a liquidity guard check for later validation.
     * @param router Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B or zero address for ETH flows.
     * @param amountADesired Desired amount associated with token A or LP amount.
     * @param amountBDesired Desired amount associated with token B.
     * @param user Address whose check is being stored.
     * @param operationType Liquidity operation being checked.
     * @return result Stored guard result for the requested liquidity action.
     */
    function storeCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOperationType operationType
    ) external returns (LiquidityV2GuardResult memory result);

    /**
     * @notice Validates the latest stored liquidity check for a user.
     * @param router Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B or zero address for ETH flows.
     * @param amountADesired Desired amount associated with token A or LP amount.
     * @param amountBDesired Desired amount associated with token B.
     * @param user Address whose stored check is validated.
     * @param operationType Liquidity operation being validated.
     */
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
