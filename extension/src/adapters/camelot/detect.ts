import type { SiteContext } from '../../shared/types';

export function detectCamelot(url: URL): SiteContext | null {
  if (!url.hostname.includes('camelot.exchange')) return null;

  return {
    protocol: 'camelot',
    chainFamily: 'evm',
    chainLabel: 'Arbitrum One',
    host: url.host,
    url: url.href,
  };
}
