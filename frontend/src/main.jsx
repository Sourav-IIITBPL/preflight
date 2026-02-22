import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './theme.css'; // Global Cyberpunk styles

// Wagmi & Tanstack Query Setup
import { WagmiProvider, createConfig, http } from 'wagmi';
import { arbitrum } from 'wagmi/chains';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient();

// Configuration for Arbitrum One
const config = createConfig({
  chains: [arbitrum],
  transports: {
    [arbitrum.id]: http(),
  },
});

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>
);