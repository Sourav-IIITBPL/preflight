import type { SiteContext } from '../../shared/types';

export function detectSaucerSwap(url: URL): SiteContext | null {
  if (!url.hostname.includes('saucerswap.finance')) return null;

  return {
    protocol: 'saucerswap',
    chainFamily: 'hedera',
    chainLabel: 'Hedera Mainnet',
    host: url.host,
    url: url.href,
  };
}
