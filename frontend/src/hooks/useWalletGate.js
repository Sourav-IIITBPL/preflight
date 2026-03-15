import { useMemo, useState } from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';

export function useWalletGate() {
  const { address, isConnected, chainId } = useAccount();
  const { connectAsync, connectors, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const [error, setError] = useState('');

  const connectWallet = async () => {
    try {
      setError('');
      const connector = connectors?.[0];
      if (!connector) throw new Error('No injected wallet connector found');
      await connectAsync({ connector });
      return { ok: true, error: '' };
    } catch (err) {
      const message = err?.message ?? 'Wallet connection failed';
      setError(message);
      return { ok: false, error: message };
    }
  };

  const disconnectWallet = () => {
    try {
      disconnect();
      setError('');
      return { ok: true, error: '' };
    } catch (err) {
      const message = err?.message ?? 'Wallet disconnect failed';
      setError(message);
      return { ok: false, error: message };
    }
  };

  const gate = useMemo(() => {
    if (!isConnected) {
      return {
        allowed: false,
        reason: 'Connect wallet to access your PreFlight report portfolio.',
      };
    }

    return { allowed: true, reason: '' };
  }, [isConnected]);

  return {
    address,
    chainId,
    isConnected,
    isConnecting,
    error,
    connectWallet,
    disconnectWallet,
    gate,
  };
}
