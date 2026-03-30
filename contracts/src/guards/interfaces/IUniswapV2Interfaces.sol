// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Uniswap V2 router interface used by guard contracts.
interface IUniswapV2Router {
    /// @notice Returns the router's associated factory.
    function factory() external view returns (address);
    /// @notice Returns the wrapped native token used by the router.
    function WETH() external view returns (address);
    /// @notice Returns the expected output amounts for an exact-input path.
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    /// @notice Returns the required input amounts for an exact-output path.
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

/// @notice Minimal Uniswap V2 factory interface used by guard contracts.
interface IUniswapV2Factory {
    /// @notice Returns the pair address for a token pair, or zero if it does not exist.
    function getPair(address tokenA, address tokenB) external view returns (address);
}

/// @notice Minimal Uniswap V2 pair interface used by guard contracts.
interface IUniswapV2Pair {
    /// @notice Returns current reserves and the last update timestamp.
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 blockTimestampLast);
    /// @notice Returns the LP token total supply.
    function totalSupply() external view returns (uint256);
    /// @notice Returns the cumulative price of token0 in token1 terms.
    function price0CumulativeLast() external view returns (uint256);
    /// @notice Returns the cumulative price of token1 in token0 terms.
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
