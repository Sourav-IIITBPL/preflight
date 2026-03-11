import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './app/App';
import { AppWagmiProvider } from './app/providers/wagmiProvider';
import { AppQueryProvider } from './app/providers/queryProvider';
import './styles/theme.css';
import './styles/globals.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <AppWagmiProvider>
      <AppQueryProvider>
        <App />
      </AppQueryProvider>
    </AppWagmiProvider>
  </React.StrictMode>
);
