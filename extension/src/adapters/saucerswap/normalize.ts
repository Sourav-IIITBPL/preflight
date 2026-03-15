import type { NormalizedIntent, SiteContext } from '../../shared/types';
import { decodeSaucerSwapCalldata } from './decode';

function asString(value: unknown) {
  return typeof value === 'bigint' ? value.toString() : String(value ?? '');
}

export function normalizeSaucerSwapIntent(site: SiteContext, payload: Record<string, unknown>): NormalizedIntent {
  const tx = payload.tx as Record<string, unknown>;
  const data = String(tx.data ?? '0x');
  const decoded = decodeSaucerSwapCalldata(data);
  const notes: string[] = ['SaucerSwap adapter is running in compatibility mode until wallet-provider specifics are finalized'];

  let summary = 'Captured SaucerSwap transaction intent';
  let operationType = String(payload.method ?? 'wallet_sendTransaction').toUpperCase();
  let tokenIn: string | undefined;
  let tokenOut: string | undefined;
  let path: string[] | undefined;
  let amountIn: string | undefined;
  let amountOutMin: string | undefined;

  if (decoded) {
    operationType = decoded.functionName.toUpperCase();
    summary = `${decoded.functionName} on SaucerSwap`;
    const args = decoded.args as readonly unknown[];
    const candidatePath = Array.isArray(args[2]) ? (args[2] as string[]) : [];
    path = candidatePath.length ? candidatePath : undefined;
    tokenIn = candidatePath[0];
    tokenOut = candidatePath[candidatePath.length - 1];
    amountIn = asString(args[0] ?? '0');
    amountOutMin = asString(args[1] ?? '0');
  } else {
    notes.push('Unable to decode calldata with the current SaucerSwap ABI set');
  }

  return {
    id: `intent_${Date.now()}`,
    protocol: 'saucerswap',
    chainFamily: site.chainFamily,
    networkLabel: site.chainLabel,
    operationType,
    method: String(payload.method ?? 'wallet_sendTransaction'),
    account: typeof payload.account === 'string' ? payload.account : undefined,
    chainId: typeof payload.chainId === 'string' ? payload.chainId : undefined,
    to: String(tx.to ?? ''),
    value: String(tx.value ?? '0'),
    data,
    summary,
    decoded: {
      tokenIn,
      tokenOut,
      path,
      amountIn,
      amountOutMin,
      notes,
    },
    rawTx: tx,
    interceptedAt: Date.now(),
  };
}
