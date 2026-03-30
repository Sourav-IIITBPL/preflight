// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @author Sourav-IITBPL
 * @notice Minimal Uniswap V2 factory interface used by the guarded routers.
 */
interface IUniswapV2Factory {
    /**
     * @notice Returns the pair address for a token pair, or zero if it does not exist.
     * @param tokenA First token in the pair.
     * @param tokenB Second token in the pair.
     * @return Pair address for the token pair.
     */
    function getPair(address tokenA, address tokenB) external view returns (address);
}

/**
 * @author Sourav-IITBPL
 * @notice Minimal Uniswap V2 pair interface used by the guarded routers and guards.
 */
interface IUniswapV2Pair {
    /// @notice Returns current reserves and the timestamp of the latest reserve update.
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    /// @notice Returns the LP token total supply.
    function totalSupply() external view returns (uint256);
    /// @notice Returns the cumulative price of token0 expressed in token1 terms.
    function price0CumulativeLast() external view returns (uint256);
    /// @notice Returns the cumulative price of token1 expressed in token0 terms.
    function price1CumulativeLast() external view returns (uint256);
    /// @notice Returns the pair's token0 address.
    function token0() external view returns (address);
    /// @notice Returns the pair's token1 address.
    function token1() external view returns (address);
    /// @notice Returns the factory that created the pair.
    function factory() external view returns (address);
    /// @notice Returns the last recorded invariant when fee accounting is enabled.
    function kLast() external view returns (uint256);
}

/**
 * @author Sourav-IITBPL
 * @notice Minimal Uniswap V2 router interface used by the guarded routers.
 */
interface IUniswapV2Router {
    /// @notice Returns the router's associated factory.
    function factory() external view returns (address);
    /// @notice Returns the router's wrapped native token.
    function WETH() external view returns (address);

    /**
     * @notice Adds liquidity to a token-token pool.
     * @return amountA Actual amount of tokenA supplied.
     * @return amountB Actual amount of tokenB supplied.
     * @return liquidity LP tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /**
     * @notice Adds liquidity to a token-ETH pool.
     * @return amountToken Actual token amount supplied.
     * @return amountETH Actual ETH amount supplied.
     * @return liquidity LP tokens minted.
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /**
     * @notice Removes liquidity from a token-token pool.
     * @return amountA Amount of tokenA returned.
     * @return amountB Amount of tokenB returned.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /**
     * @notice Removes liquidity from a token-ETH pool.
     * @return amountToken Amount of tokens returned.
     * @return amountETH Amount of ETH returned.
     */
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    /**
     * @notice Executes an exact-input token-for-token swap.
     * @return amounts Per-hop amounts returned by the router.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Executes an exact-output token-for-token swap.
     * @return amounts Per-hop amounts returned by the router.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Executes an exact-input ETH-for-token swap.
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Executes an exact-output ETH-for-token swap.
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    /// @notice Executes an exact-input token-for-ETH swap.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Executes an exact-output token-for-ETH swap.
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
