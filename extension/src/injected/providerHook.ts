import { buildInterceptionError } from './txInterceptor';

declare global {
  interface Window {
    ethereum?: {
      request(args: { method: string; params?: unknown[] | object }): Promise<unknown>;
      on?(event: string, handler: (...args: unknown[]) => void): void;
    };
  }
}

let isActive = false;
let bypassNext = false;

function post(type: string, payload: unknown) {
  window.postMessage({ source: 'preflight-injected', type, payload }, '*');
}

async function captureProviderStatus() {
  const provider = window.ethereum;
  if (!provider) {
    post('PF_PROVIDER_READY', { walletAvailable: false });
    return;
  }

  post('PF_PROVIDER_READY', { walletAvailable: true });

  try {
    const [account, chainId] = await Promise.all([
      provider.request({ method: 'eth_accounts' }).then((value) => Array.isArray(value) ? String(value[0] ?? '') : ''),
      provider.request({ method: 'eth_chainId' }).then((value) => String(value ?? '')),
    ]);

    post('PF_PROVIDER_STATUS', {
      walletConnected: Boolean(account),
      account,
      chainId,
    });
  } catch {
    post('PF_PROVIDER_STATUS', {
      walletConnected: false,
    });
  }
}

function hookProvider() {
  const provider = window.ethereum;
  if (!provider || typeof provider.request !== 'function') return false;
  const originalRequest = provider.request.bind(provider);

  provider.request = async (args) => {
    const method = String(args.method ?? '');
    const params = Array.isArray(args.params) ? args.params : [];

    if (bypassNext) {
      bypassNext = false;
      return originalRequest(args);
    }

    if (isActive && (method === 'eth_sendTransaction' || method === 'wallet_sendTransaction')) {
      const tx = (params[0] ?? {}) as Record<string, unknown>;
      const [account, chainId] = await Promise.all([
        originalRequest({ method: 'eth_accounts' }).then((value) => Array.isArray(value) ? String(value[0] ?? '') : ''),
        originalRequest({ method: 'eth_chainId' }).then((value) => String(value ?? '')),
      ]);

      post('PF_PROVIDER_INTERCEPTED', {
        method,
        tx,
        account,
        chainId,
        url: window.location.href,
      });

      throw buildInterceptionError();
    }

    return originalRequest(args);
  };

  provider.on?.('accountsChanged', (accounts) => {
    post('PF_PROVIDER_STATUS', {
      walletConnected: Array.isArray(accounts) && accounts.length > 0,
      account: Array.isArray(accounts) ? String(accounts[0] ?? '') : '',
    });
  });

  provider.on?.('chainChanged', (chainId) => {
    post('PF_PROVIDER_STATUS', { chainId: String(chainId ?? '') });
  });

  void captureProviderStatus();
  return true;
}

export function bootProviderHook() {
  const poll = window.setInterval(() => {
    const ok = hookProvider();
    if (ok) {
      window.clearInterval(poll);
    }
  }, 400);

  window.addEventListener('message', async (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object' || data.source !== 'preflight-content') return;

    if (data.type === 'PF_INJECTED_SET_ACTIVE') {
      isActive = Boolean(data.payload?.active);
      await captureProviderStatus();
      return;
    }

    if (data.type === 'PF_INJECTED_EXECUTE_ORIGINAL') {
      const provider = window.ethereum;
      if (!provider) {
        post('PF_EXECUTION_RESULT', { ok: false, error: 'Wallet provider not available in page context' });
        return;
      }

      try {
        bypassNext = true;
        const hash = await provider.request({ method: 'eth_sendTransaction', params: [data.payload?.tx ?? {}] });
        post('PF_EXECUTION_RESULT', { ok: true, hash });
      } catch (error) {
        post('PF_EXECUTION_RESULT', { ok: false, error: error instanceof Error ? error.message : 'Execution request failed' });
      }
    }
  });
}
