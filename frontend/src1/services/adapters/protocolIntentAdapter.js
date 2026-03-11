import { INTENT_CHANNEL, INTENT_STORAGE_KEY } from '../../shared/constants/app';
import { readJsonStorage, writeJsonStorage } from '../../shared/utils/storage';

export function createDefaultIntent() {
  return {
    id: `intent_${Date.now()}`,
    source: 'manual-launchpad',
    network: 'arbitrum',
    protocol: 'Camelot',
    targetUrl: 'https://app.camelot.exchange',
    from: '0x1111111111111111111111111111111111111111',
    type: 'SWAP',
    opType: 'EXACT_TOKENS_IN',
    walletConnectedOnTarget: false,
    updatedAt: Date.now(),
    payload: {
      pair: 'WETH/USDC',
      amount: '1.00',
      tokenIn: 'WETH',
      tokenOut: 'USDC',
      routerAddress: '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
      vaultAddress: '0x0000000000000000000000000000000000000000',
      data: '0x',
      notes: '',
    },
  };
}

function normalizeIntent(input) {
  const fallback = createDefaultIntent();
  const merged = {
    ...fallback,
    ...(input ?? {}),
    payload: {
      ...fallback.payload,
      ...(input?.payload ?? {}),
    },
    updatedAt: Date.now(),
  };

  return merged;
}

export function readStoredIntent() {
  return normalizeIntent(readJsonStorage(INTENT_STORAGE_KEY, createDefaultIntent()));
}

export function createProtocolIntentBridge({ onIntent }) {
  let channel;

  const emitIntent = (next) => {
    const normalized = normalizeIntent(next);
    writeJsonStorage(INTENT_STORAGE_KEY, normalized);
    onIntent(normalized);
    if (channel) {
      channel.postMessage({ type: 'PREFLIGHT_INTENT_UPDATE', payload: normalized });
    }
  };

  const onStorage = (event) => {
    if (event.key !== INTENT_STORAGE_KEY || !event.newValue) return;
    try {
      const parsed = JSON.parse(event.newValue);
      onIntent(normalizeIntent(parsed));
    } catch {
      // no-op
    }
  };

  const onMessage = (event) => {
    const data = event?.data;
    if (!data || typeof data !== 'object') return;

    if (data.type === 'PREFLIGHT_INTENT_UPDATE') {
      emitIntent(data.payload);
    }

    if (data.type === 'PREFLIGHT_WALLET_STATUS') {
      const current = readStoredIntent();
      emitIntent({
        ...current,
        walletConnectedOnTarget: Boolean(data.connected),
      });
    }
  };

  const onWindowMessage = (event) => {
    const data = event?.data;
    if (!data || typeof data !== 'object') return;
    if (!String(data.type ?? '').startsWith('PREFLIGHT_')) return;
    onMessage({ data });
  };

  if ('BroadcastChannel' in window) {
    channel = new BroadcastChannel(INTENT_CHANNEL);
    channel.onmessage = onMessage;
  }

  window.addEventListener('storage', onStorage);
  window.addEventListener('message', onWindowMessage);

  return {
    publishIntent: emitIntent,
    disconnect: () => {
      if (channel) channel.close();
      window.removeEventListener('storage', onStorage);
      window.removeEventListener('message', onWindowMessage);
    },
  };
}
