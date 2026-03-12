import React, { useMemo, useState } from 'react';
import { APP_ROUTES } from './routes';
import { APP_NAME, NETWORK_LABEL } from '../shared/constants/app';
import { useLaunchSession } from '../features/launchpad/hooks/useLaunchSession';
import { useWalletGate } from '../features/preflight-session/hooks/useWalletGate';
import LaunchpadPage from '../pages/LaunchpadPage';
import DexPage from '../pages/DexPage';
import PortfolioPage from '../pages/PortfolioPage';
import ToastStack from '../shared/ui/ToastStack';
import Button from '../shared/ui/Button';
import Badge from '../shared/ui/Badge';

export default function App() {
  const [route, setRoute] = useState(APP_ROUTES.HOME);
  const launchSession = useLaunchSession();
  const walletGate = useWalletGate();
  const isDexRoute = route === APP_ROUTES.DEX;

  const walletLabel = useMemo(() => {
    if (!walletGate.address) return 'Connect Wallet';
    return `${walletGate.address.slice(0, 6)}...${walletGate.address.slice(-4)}`;
  }, [walletGate.address]);

  const navItems = useMemo(() => {
    const items = [{ key: APP_ROUTES.HOME, label: 'Launchpad' }];
    if (launchSession.selectedDex) {
      items.push({ key: APP_ROUTES.DEX, label: 'DEX' });
    }
    items.push({ key: APP_ROUTES.PORTFOLIO, label: 'My PreFlight Reports & Rewards' });
    return items;
  }, [launchSession.selectedDex]);

  const onWalletAction = async () => {
    if (walletGate.isConnected) {
      const result = walletGate.disconnectWallet();
      if (result.ok) {
        launchSession.pushToast('Wallet disconnected');
      } else {
        launchSession.pushToast('Wallet disconnect failed', result.error);
      }
      return;
    }

    const result = await walletGate.connectWallet();
    if (result.ok) {
      launchSession.pushToast('Wallet connected', 'You can now run PreFlight checks');
    } else {
      launchSession.pushToast('Wallet connection failed', result.error);
    }
  };

  return (
    <div className="min-h-screen bg-brand-dark text-slate-100 relative overflow-hidden">
      <div className="pointer-events-none absolute inset-0 panel-grid-bg" />
      <div className="pointer-events-none absolute -top-24 -right-24 h-96 w-96 rounded-full bg-brand-cyan/10 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-24 -left-16 h-96 w-96 rounded-full bg-slate-900/50 blur-3xl" />

      <header className="sticky top-0 z-40 border-b border-white/10 bg-brand-dark/90 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl items-center gap-4 px-4 py-3 md:px-6">
          <div className="flex items-center gap-2">
            <div className="h-8 w-8 rounded-lg bg-brand-cyan text-black font-black grid place-items-center">P</div>
            <div>
              <div className="text-sm font-black uppercase tracking-[0.22em]">{APP_NAME}</div>
              <div className="text-[10px] uppercase tracking-[0.16em] text-slate-400">{NETWORK_LABEL}</div>
            </div>
          </div>

          <nav className="ml-2 flex flex-wrap items-center gap-2">
            {navItems.map((item) => (
              <button
                key={item.key}
                className={`rounded-lg px-3 py-2 text-xs font-bold uppercase tracking-wider transition ${
                  route === item.key
                    ? 'bg-white/12 text-white border border-white/20'
                    : 'bg-transparent text-slate-400 border border-transparent hover:text-white hover:border-white/15'
                }`}
                onClick={() => setRoute(item.key)}
              >
                {item.label}
              </button>
            ))}
          </nav>

          <div className="ml-auto flex items-center gap-3">
            <Badge label={`Reports: ${launchSession.reportCount}`} tone="info" />
            <Button variant={walletGate.isConnected ? 'ghost' : 'primary'} onClick={onWalletAction}>
              {walletLabel}
            </Button>
          </div>
        </div>
      </header>

      <main
        className={`relative z-10 min-h-[calc(100vh-73px)] ${
          isDexRoute ? 'w-full px-0 py-0' : 'mx-auto max-w-7xl px-4 py-6 md:px-6 md:py-8'
        }`}
      >
        {route === APP_ROUTES.HOME ? <LaunchpadPage launchSession={launchSession} onDexSelected={() => setRoute(APP_ROUTES.DEX)} /> : null}

        {route === APP_ROUTES.DEX ? <DexPage launchSession={launchSession} walletGate={walletGate} /> : null}

        {route === APP_ROUTES.PORTFOLIO ? (
          <PortfolioPage
            walletGate={walletGate}
            mintedReports={launchSession.mintedReports}
            clearReports={launchSession.clearReports}
          />
        ) : null}
      </main>

      <ToastStack items={launchSession.toasts} />
    </div>
  );
}
