export const CONTRACTS = {
  router: import.meta.env.VITE_PREFLIGHT_ROUTER_ADDRESS ?? '',
  riskReportNft: import.meta.env.VITE_PREFLIGHT_REPORT_NFT_ADDRESS ?? '',
};

export const CONTRACT_ABI = {
  router: [
    'function executeSwap(address pool, address tokenIn, uint256 amountIn, bool allowRisk) external returns (uint256)',
    'function executeDeposit(address vault, uint256 amount, address receiver, bool allowRisk) external returns (uint256)',
  ],
  riskReportNft: [
    'function mintReport(address to, string reportData) external returns (uint256)',
    'function tokenURI(uint256 tokenId) view returns (string)',
  ],
};
