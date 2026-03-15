import React, { useEffect, useState } from 'react';
import LandingSection from './components/LandingSection';
import InstallPage from './components/InstallPage';
import PortfolioPage from './components/PortfolioPage';
import Navbar from './components/layout/Navbar';
import ToastStack from './components/ui/ToastStack';
import Logo from './components/ui/Logo';
import { ROUTES } from './constants';
import { useWalletGate } from './hooks/useWalletGate';
import { useToasts } from './hooks/useToasts';
import { usePortfolioReports } from './hooks/usePortfolioReports';
import { motion, AnimatePresence } from 'framer-motion';

function getInitialRoute() {
  const hash = window.location.hash.replace('#', '');
  return Object.values(ROUTES).includes(hash) ? hash : ROUTES.HOME;
}

export default function App() {
  const [route, setRoute] = useState(getInitialRoute);
  const walletGate = useWalletGate();
  const toasts = useToasts();
  const portfolio = usePortfolioReports({ address: walletGate.address, isConnected: walletGate.isConnected });

  useEffect(() => {
    const onHashChange = () => setRoute(getInitialRoute());
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  const navigate = (nextRoute) => {
    window.location.hash = nextRoute;
    setRoute(nextRoute);
  };

  const onWalletAction = async () => {
    if (walletGate.isConnected) {
      const result = walletGate.disconnectWallet();
      if (result.ok) {
        toasts.pushToast('Wallet disconnected');
      } else {
        toasts.pushToast('Wallet disconnect failed', result.error);
      }
      return;
    }

    const result = await walletGate.connectWallet();
    if (result.ok) {
      toasts.pushToast('Wallet connected', 'Portfolio sync is now available');
    } else {
      toasts.pushToast('Wallet connection failed', result.error);
    }
  };

  const onRefreshPortfolio = async () => {
    const next = await portfolio.refreshOnchain();
    if (next.length) {
      toasts.pushToast('Portfolio refreshed', `${next.length} on-chain report${next.length === 1 ? '' : 's'} loaded`);
      return;
    }

    if (!portfolio.error) {
      toasts.pushToast('Portfolio refreshed', 'No on-chain reports found yet');
    }
  };

  let content;
  if (route === ROUTES.INSTALL) {
    content = <InstallPage onOpenPortfolio={() => navigate(ROUTES.PORTFOLIO)} />;
  } else if (route === ROUTES.PORTFOLIO) {
    content = (
      <PortfolioPage
        walletGate={walletGate}
        portfolio={portfolio}
        onWalletAction={onWalletAction}
        onRefresh={onRefreshPortfolio}
      />
    );
  } else {
    content = <LandingSection onOpenInstall={() => navigate(ROUTES.INSTALL)} onOpenPortfolio={() => navigate(ROUTES.PORTFOLIO)} />;
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-brand-dark text-slate-100">
      {/* MASSIVE BACKGROUND WATERMARK - Static & Professional */}
      <div className="fixed inset-0 pointer-events-none z-0 flex items-center justify-center opacity-[0.015]">
        <div className="w-[120vmax] h-[120vmax]">
          <Logo className="w-full h-full" animated={false} />
        </div>
      </div>

      <div className="panel-grid-bg pointer-events-none absolute inset-0 z-0" />
      
      <div className="pointer-events-none absolute -right-24 -top-24 h-96 w-96 rounded-full bg-brand-cyan/10 blur-3xl z-0" />
      <div className="pointer-events-none absolute -bottom-24 -left-16 h-96 w-96 rounded-full bg-slate-900/50 blur-3xl z-0" />

      <Navbar route={route} onNavigate={navigate} walletGate={walletGate} reportCount={portfolio.summary.total} onWalletAction={onWalletAction} />

      <main className="relative z-10 mx-auto min-h-[calc(100vh-73px)] max-w-7xl px-4 py-6 md:px-6 md:py-8">
        <AnimatePresence mode="wait">
          <motion.div
            key={route}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.3 }}
          >
            {content}
          </motion.div>
        </AnimatePresence>
      </main>

      <ToastStack items={toasts.items} />
    </div>
  );
}
