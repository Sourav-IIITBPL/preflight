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
    id: 'camelot-arbitrum',
    name: 'Camelot',
    chain: 'Arbitrum',
    network: 'Arbitrum One',
    description: 'EVM-native AMM coverage for swap and liquidity paths on Arbitrum.',
    website: 'https://app.camelot.exchange',
    status: 'Extension adapter planned for v1',
  },
  {
    id: 'saucerswap-hedera',
    name: 'SaucerSwap',
    chain: 'Hedera',
    network: 'Hedera Mainnet',
    description: 'Hedera-focused DEX support under the same PreFlight extension shell.',
    website: 'https://www.saucerswap.finance',
    status: 'Protocol adapter planned for v1',
  },
];

export const INSTALL_STEPS = [
  {
    step: '01',
    title: 'Install the PreFlight extension',
    body: 'Use the install package from this site and load it into Chrome as an unpacked extension for the demo.',
  },
  {
    step: '02',
    title: 'Pin and activate PreFlight',
    body: 'Pin the extension, open Camelot or SaucerSwap normally, then activate PreFlight from the popup.',
  },
  {
    step: '03',
    title: 'Trade on the official DEX',
    body: 'Keep using the official DEX UI. PreFlight injects its floating button and sidebar onto the real page.',
  },
  {
    step: '04',
    title: 'Review, mint, execute',
    body: 'The extension intercepts the intent, runs CRE and on-chain checks, shows the report, then routes execution through PreFlightRouter.',
  },
];

export const WORKFLOW_STEPS = [
  'User opens Camelot or SaucerSwap normally.',
  'PreFlight extension is activated on the live DEX page.',
  'The extension intercepts transaction intent before signature.',
  'Calldata, route, amounts, and network context are normalized.',
  'CRE runs off-chain verification and guards run on-chain reads.',
  'A centered report view explains the verdict before execution.',
  'User mints a RiskReport NFT and executes through PreFlightRouter.',
];

export const COMPATIBILITY_NOTES = [
  'Chrome or Chromium browsers are the first demo target.',
  'MetaMask connection happens on the official DEX page, not inside the PreFlight website.',
  'The website is the portfolio, install, and product trust surface. Live interception belongs to the extension runtime.',
  'Configure VITE_PREFLIGHT_REPORT_NFT_ADDRESS to enable on-chain report discovery on the portfolio page.',
];
