export const APP_NAME = 'PreFlight';
export const NETWORK_LABEL = 'Arbitrum One';
export const REPORT_STALE_AFTER_MS = 10_000;
export const TOAST_TTL_MS = 4_000;
export const INTENT_CHANNEL = 'preflight_intent_channel';
export const INTENT_STORAGE_KEY = 'preflight.intent.v1';
export const REPORT_STORAGE_KEY = 'preflight.reports.v1';
export const LAUNCH_STORAGE_KEY = 'preflight.launch.active.v1';
export const DEX_SELECTION_STORAGE_KEY = 'preflight.dex.selection.v1';

export const SUPPORTED_DEXES = [
  {
    id: 'camelot-arbitrum',
    name: 'Camelot',
    chain: 'Arbitrum',
    url: 'https://app.camelot.exchange',
    tag: 'Arbitrum Mainnet',
    type: 'swap-liquidity',
  },
  {
    id: 'saucerswap-hedera',
    name: 'SaucerSwap',
    chain: 'Hedera',
    url: 'https://www.saucerswap.finance',
    tag: 'Hedera Mainnet',
    type: 'swap-liquidity',
  },
];
