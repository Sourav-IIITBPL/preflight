import React, { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Chrome, LayoutTemplate, Shield, Activity, RefreshCw } from 'lucide-react';
import type { SiteSession, StoredReport } from '../shared/types';
import HomePage from './pages/HomePage';
import PortfolioPage from './pages/PortfolioPage';

type TabKey = 'home' | 'portfolio';

async function getActiveSite(): Promise<SiteSession | undefined> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return undefined;

  try {
    const response = await chrome.tabs.sendMessage(tab.id, { type: 'PF_GET_PAGE_STATE' }) as {
      ok: boolean;
      site?: SiteSession;
      activated?: boolean;
      account?: string;
      chainId?: string;
      intentSummary?: string;
    };

    if (!response?.ok || !response.site) return undefined;

    return {
      protocol: response.site.protocol,
      host: response.site.host,
      url: response.site.url,
      activated: Boolean(response.activated),
      account: response.account,
      chainId: response.chainId,
      lastIntentSummary: response.intentSummary,
      updatedAt: Date.now(),
    };
  } catch {
    return undefined;
  }
}

async function activateCurrentSite() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error('No active tab found');
  await chrome.tabs.sendMessage(tab.id, { type: 'PF_ACTIVATE_SITE' });
}

async function getStoredReports(): Promise<StoredReport[]> {
  try {
    return await chrome.runtime.sendMessage({ type: 'PF_GET_REPORTS' }) as StoredReport[];
  } catch {
    return [];
  }
}

export default function App() {
  const [tab, setTab] = useState<TabKey>('home');
  const [activeSite, setActiveSite] = useState<SiteSession | undefined>();
  const [reports, setReports] = useState<StoredReport[]>([]);
  const [status, setStatus] = useState('Ready');
  const [isRefreshing, setIsRefreshing] = useState(false);

  const refresh = async () => {
    setIsRefreshing(true);
    try {
      const [site, storedReports] = await Promise.all([
        getActiveSite(),
        getStoredReports()
      ]);
      setActiveSite(site);
      setReports(storedReports || []);
    } finally {
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    void refresh();
  }, []);

  const handleActivate = async () => {
    try {
      setStatus('Activating...');
      await activateCurrentSite();
      await refresh();
      setStatus('PreFlight Active');
      setTimeout(() => setStatus('Ready'), 3000);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Activation failed');
    }
  };

  const openWebsite = () => {
    void chrome.tabs.create({ url: 'http://localhost:5173' });
  };

  return (
    <div className="relative min-h-[540px] w-[380px] overflow-hidden bg-brand-dark text-slate-100 selection:bg-brand-cyan/30 selection:text-white">
      {/* Background elements */}
      <div className="panel-grid-bg pointer-events-none absolute inset-0 opacity-40" />
      <div className="pointer-events-none absolute -right-24 -top-24 h-64 w-64 rounded-full bg-brand-cyan/10 blur-3xl" />
      
      {/* Header */}
      <header className="relative z-10 border-b border-white/10 px-5 py-5 backdrop-blur-md bg-brand-dark/40">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <motion.div 
              className="grid h-10 w-10 place-items-center rounded-xl bg-brand-cyan font-black text-black shadow-[0_0_20px_rgba(0,242,254,0.3)]"
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              P
            </motion.div>
            <div>
              <div className="text-sm font-black uppercase tracking-[0.25em] text-white">PreFlight</div>
              <div className="text-[9px] font-bold uppercase tracking-[0.2em] text-slate-500">Security Extension</div>
            </div>
          </div>
          
          <motion.button 
            className="p-2 text-slate-400 hover:text-brand-cyan transition-colors"
            onClick={refresh}
            animate={{ rotate: isRefreshing ? 360 : 0 }}
            transition={{ duration: 1, repeat: isRefreshing ? Infinity : 0, ease: "linear" }}
          >
            <RefreshCw size={16} />
          </motion.button>
        </div>

        <nav className="mt-5 flex gap-2">
          <button 
            className={`btn-ghost flex-1 py-2.5 transition-all ${tab === 'home' ? 'border-brand-cyan/30 bg-brand-cyan/10 text-brand-cyan' : ''}`} 
            onClick={() => setTab('home')}
          >
            <Shield size={13} /> Home
          </button>
          <button 
            className={`btn-ghost flex-1 py-2.5 transition-all ${tab === 'portfolio' ? 'border-brand-cyan/30 bg-brand-cyan/10 text-brand-cyan' : ''}`} 
            onClick={() => setTab('portfolio')}
          >
            <LayoutTemplate size={13} /> Portfolio
          </button>
        </nav>
      </header>

      {/* Content */}
      <main className="relative z-10 h-[380px] overflow-y-auto px-5 py-6">
        <AnimatePresence mode="wait">
          <motion.div
            key={tab}
            initial={{ opacity: 0, x: tab === 'home' ? -10 : 10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: tab === 'home' ? 10 : -10 }}
            transition={{ duration: 0.2, ease: "easeInOut" }}
          >
            {tab === 'home' ? (
              <HomePage activeSite={activeSite} onActivate={handleActivate} onOpenWebsite={openWebsite} />
            ) : (
              <PortfolioPage reports={reports} onOpenWebsite={openWebsite} />
            )}
          </motion.div>
        </AnimatePresence>
      </main>

      {/* Footer */}
      <footer className="relative z-10 border-t border-white/10 px-5 py-3.5 backdrop-blur-md bg-brand-dark/40">
        <div className="flex items-center justify-between text-[10px] font-bold tracking-wider">
          <div className="flex items-center gap-2 text-slate-500">
            <motion.div 
              animate={{ opacity: [0.5, 1, 0.5] }}
              transition={{ duration: 2, repeat: Infinity }}
              className="h-1.5 w-1.5 rounded-full bg-brand-cyan shadow-[0_0_5px_rgba(0,242,254,1)]"
            />
            <span className="uppercase">{status}</span>
          </div>
          <button className="flex items-center gap-1.5 text-brand-cyan hover:underline transition-all uppercase" onClick={openWebsite}>
            <Chrome size={12} /> Dashboard <Activity size={12} />
          </button>
        </div>
      </footer>
    </div>
  );
}
