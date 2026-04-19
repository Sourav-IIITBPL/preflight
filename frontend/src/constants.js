export const APP_NAME = 'PreFlight';
export const NETWORK_LABEL = 'Extension-First Security Layer';
export const REPORT_STORAGE_KEY = 'preflight.reports.v1';
export const TOAST_TTL_MS = 4000;

export const ROUTES = {
  HOME: 'home',
  INSTALL: 'install',
  PORTFOLIO: 'portfolio',
};

export const SUPPORTED_DEXES = [
  {
    id: 'uniswap',
    name: 'Uniswap',
    logo: 'https://cryptologos.cc/logos/uniswap-uni-logo.png',
  },
  {
    id: 'sushiswap',
    name: 'Sushiswap',
    logo: 'https://cryptologos.cc/logos/sushiswap-sushi-logo.png',
  },
  {
    id: 'pancakeswap',
    name: 'PancakeSwap',
    logo: 'https://cryptologos.cc/logos/pancakeswap-cake-logo.png',
  },
  {
    id: 'camelot',
    name: 'Camelot',
    logo: 'https://cryptologos.cc/logos/arbitrum-arb-logo.png',
  },
  {
    id: 'balancer',
    name: 'Balancer',
    logo: 'https://cryptologos.cc/logos/balancer-bal-logo.png',
  },
  {
    id: 'saucerswap',
    name: 'SaucerSwap',
    logo: 'https://raw.githubusercontent.com/SaucerSwap/saucerswap-token-list/main/assets/SAUCE/logo.png', // Fallback as user didn't provide link
  },
  {
    id: 'baseswap',
    name: 'BaseSwap',
    logo: 'https://baseswap.fi/images/logo.png', // Fallback
  }
];

export const SUPPORTED_VAULTS = [
  {
    id: 'beefy',
    name: 'Beefy',
    logo: 'https://cryptologos.cc/logos/beefy-finance-bifi-logo.png',
  },
  {
    id: 'yearn',
    name: 'Yearn',
    logo: 'https://cryptologos.cc/logos/yearn-finance-yfi-logo.png',
  }
];

export const INSTALL_STEPS = [
  {
    step: '01',
    title: 'Install the PreFlight extension',
    body: 'Download the extension package and load it into your browser.',
  },
  {
    step: '02',
    title: 'Connect your wallet',
    body: 'Link your MetaMask or preferred wallet to PreFlight.',
  },
  {
    step: '03',
    title: 'Enable interception',
    body: 'Toggle on PreFlight protection to start monitoring transactions.',
  },
  {
    step: '04',
    title: 'Interact with dApps',
    body: 'Use Uniswap, Beefy, or other supported dApps normally.',
  },
];

export const WORKFLOW_STEPS = [
  'User initiates transaction (e.g. swap) on the official DEX or Vault.',
  'PreFlight Extension intercepts the transaction before signing.',
  'Off-chain Fork Simulation is executed in a replicated state.',
  'On-chain Guards validate transaction invariants (SwapGuard, TokenGuard, VaultGuard).',
  'Risk report is generated and shown to the user.',
  'Risk Report NFT is minted on-chain as a verifiable proof.',
  'Transaction is executed only after successful verification.',
];

export const YT_DEMO_URL = "https://www.youtube.com/embed/FNSTfgVRpTs";

export const COMPATIBILITY_NOTES = [
  'Currently supports Uniswap V2 pools and its forks (excluding fee-on-transfer).',
  'Supports ERC4626 vault operations.',
  'Available on Testnets: Base Sepolia, Arbitrum Sepolia, Sepolia.',
  'Mainnet integration coming soon.',
];
