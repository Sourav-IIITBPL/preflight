import type { SiteContext } from '../shared/types';
import { detectCamelot } from '../adapters/camelot/detect';
import { detectSaucerSwap } from '../adapters/saucerswap/detect';

export function detectSupportedSite(urlString: string): SiteContext | null {
  const url = new URL(urlString);
  return detectCamelot(url) ?? detectSaucerSwap(url);
}
