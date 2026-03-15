import type { NormalizedIntent, SiteContext } from '../../shared/types';
import { decodeCamelotCalldata } from './decode';

function asString(value: unknown) {
  return typeof value === 'bigint' ? value.toString() : String(value ?? '');
}

export function normalizeCamelotIntent(site: SiteContext, payload: Record<string, unknown>): NormalizedIntent {
  const tx = payload.tx as Record<string, unknown>;
  const data = String(tx.data ?? '0x');
  const value = String(tx.value ?? '0');
  const decoded = decodeCamelotCalldata(data);

  let summary = 'Captured transaction intent';
  let operationType = payload.method === 'eth_sendTransaction' ? 'TRANSACTION' : String(payload.method ?? 'TRANSACTION');
  const normalized = {
    tokenIn: undefined as string | undefined,
    tokenOut: undefined as string | undefined,
    path: undefined as string[] | undefined,
    amountIn: undefined as string | undefined,
    amountOutMin: undefined as string | undefined,
    notes: [] as string[],
  };

  if (decoded) {
    operationType = decoded.functionName.toUpperCase();
    const args = decoded.args as readonly unknown[];
    summary = `${decoded.functionName} on Camelot`;

    if (decoded.functionName.startsWith('swap')) {
      const path = Array.isArray(args[2]) ? (args[2] as string[]) : Array.isArray(args[1]) ? (args[1] as string[]) : [];
      normalized.path = path;
      normalized.tokenIn = path[0];
      normalized.tokenOut = path[path.length - 1];
      normalized.amountIn = asString(args[0] ?? value);
      normalized.amountOutMin = asString(args[1] ?? args[0] ?? '0');
    }

    if (decoded.functionName.startsWith('addLiquidity') || decoded.functionName.startsWith('removeLiquidity')) {
      normalized.tokenIn = asString(args[0]);
      normalized.tokenOut = asString(args[1] ?? '');
      normalized.amountIn = asString(args[2] ?? '0');
      normalized.amountOutMin = asString(args[3] ?? '0');
    }
  } else {
    normalized.notes.push('Calldata could not be decoded against the Camelot adapter ABI set');
  }

  return {
    id: `intent_${Date.now()}`,
    protocol: 'camelot',
    chainFamily: site.chainFamily,
    networkLabel: site.chainLabel,
    operationType,
    method: String(payload.method ?? 'eth_sendTransaction'),
    account: typeof payload.account === 'string' ? payload.account : undefined,
    chainId: typeof payload.chainId === 'string' ? payload.chainId : undefined,
    to: String(tx.to ?? ''),
    value,
    data,
    summary,
    decoded: normalized,
    rawTx: tx,
    interceptedAt: Date.now(),
  };
}
