import { decodeFunctionData, parseAbi } from 'viem';

const routerAbi = parseAbi([
  'function swapExactTokensForTokens(uint256 amountIn,uint256 amountOutMin,address[] path,address to,uint256 deadline)',
  'function swapExactETHForTokens(uint256 amountOutMin,address[] path,address to,uint256 deadline)',
  'function swapExactTokensForETH(uint256 amountIn,uint256 amountOutMin,address[] path,address to,uint256 deadline)',
  'function addLiquidity(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline)',
  'function addLiquidityETH(address token,uint256 amountTokenDesired,uint256 amountTokenMin,uint256 amountETHMin,address to,uint256 deadline)',
  'function removeLiquidity(address tokenA,address tokenB,uint256 liquidity,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline)',
  'function removeLiquidityETH(address token,uint256 liquidity,uint256 amountTokenMin,uint256 amountETHMin,address to,uint256 deadline)'
]);

export function decodeCamelotCalldata(data: string) {
  if (!data || data === '0x') return null;

  try {
    const decoded = decodeFunctionData({ abi: routerAbi, data: data as `0x${string}` });
    return decoded;
  } catch {
    return null;
  }
}
