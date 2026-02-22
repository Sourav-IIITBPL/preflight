export const ROUTER_ADDR = "0xYour_PreFlightRouter_Address";
export const NFT_ADDR = "0xYour_RiskReportNFT_Address";
export const VAULT_GUARD_ADDR = "0xYour_VaultGuard_Address";
export const SWAP_GUARD_ADDR = "0xYour_SwapGuard_Address";

export const ROUTER_ABI = [
    "function executeDeposit(address vault, uint256 amount, address receiver, bool allowRisk) external returns (uint256)",
    "function executeSwap(address pool, address tokenIn, uint256 amountIn, bool allowRisk) external returns (uint256)",
    "event TransactionGuarded(address indexed user, bool success, uint8 riskScore)"
];

export const GUARD_ABI = [
    "function checkVaultwithPreview(address vault, uint256 amount, bool isDeposit) public view returns (uint8 result, uint256 shares, uint256 assets)",
    "function swapCheckV2Pool(address pool, address tokenIn, uint256 amountIn) public view returns (uint8 result, uint256 amountOut)"
];

export const NFT_ABI = [
    "function mintReport(address to, string memory reportData) external returns (uint256)",
    "function tokenURI(uint256 tokenId) public view returns (string memory)"
];