export const CONTRACTS = {
  riskReportNft: import.meta.env.VITE_PREFLIGHT_REPORT_NFT_ADDRESS ?? '',
  rpcUrl: 'https://arb1.arbitrum.io/rpc',
};

export const RISK_REPORT_NFT_ABI = [
  {
    "inputs": [{ "name": "owner", "type": "address" }],
    "name": "balanceOf",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "name": "owner", "type": "address" },
      { "name": "index", "type": "uint256" }
    ],
    "name": "tokenOfOwnerByIndex",
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{ "name": "tokenId", "type": "uint256" }],
    "name": "getReport",
    "outputs": [
      {
        "components": [
          { "name": "reportType", "type": "uint8" },
          { "name": "riskLevel", "type": "uint8" },
          { "name": "status", "type": "uint8" },
          { "name": "user", "type": "address" },
          { "name": "target", "type": "address" },
          { "name": "router", "type": "address" },
          { "name": "amount", "type": "uint256" },
          { "name": "previewValue", "type": "uint256" },
          { "name": "blockNumber", "type": "uint256" },
          { "name": "timestamp", "type": "uint256" },
          { "name": "checkHash", "type": "bytes32" },
          { "name": "flagsPacked", "type": "uint32" },
          { "name": "totalFlags", "type": "uint8" },
          { "name": "criticalCount", "type": "uint8" },
          { "name": "softCount", "type": "uint8" }
        ],
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];
