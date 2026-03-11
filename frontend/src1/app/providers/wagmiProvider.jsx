import React from 'react';
import { WagmiProvider, createConfig, http } from 'wagmi';
import { arbitrum } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

const wagmiConfig = createConfig({
  chains: [arbitrum],
  connectors: [injected()],
  transports: {
    [arbitrum.id]: http(),
  },
});

export function AppWagmiProvider({ children }) {
  return <WagmiProvider config={wagmiConfig}>{children}</WagmiProvider>;
}
