import React from 'react';
import { motion } from 'framer-motion';
import { APP_NAME, NETWORK_LABEL, ROUTES } from '../../constants';
import Button from '../ui/Button';
import Badge from '../ui/Badge';
import Logo from '../ui/Logo';
import { Wallet, History, Info, Menu } from 'lucide-react';

export default function Navbar({ route, onNavigate, walletGate, reportCount, onWalletAction }) {
  const walletLabel = walletGate.address
    ? `${walletGate.address.slice(0, 6)}...${walletGate.address.slice(-4)}`
    : walletGate.isConnecting
      ? 'Connecting...'
      : 'Connect Wallet';

  const items = [
    { key: ROUTES.HOME, label: 'Protocol', icon: <Info size={14} /> },
    { key: ROUTES.INSTALL, label: 'Access', icon: <Menu size={14} /> },
    { key: ROUTES.PORTFOLIO, label: 'Portfolio', icon: <History size={14} /> },
  ];

  return (
    <header className="sticky top-0 z-50 border-b border-white/5 bg-brand-dark/60 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3 md:px-6">
        {/* Brand Group */}
        <motion.button 
          className="flex items-center gap-4 group" 
          onClick={() => onNavigate(ROUTES.HOME)}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
        >
          <Logo className="h-10 w-10" animated={true} />
          <div className="hidden sm:block text-left">
            <div className="text-base font-black uppercase tracking-[0.25em] text-white leading-none">{APP_NAME}</div>
            <div className="mt-1 text-[9px] font-bold uppercase tracking-[0.2em] text-brand-cyan/60">{NETWORK_LABEL}</div>
          </div>
        </motion.button>

        {/* Navigation Group */}
        <nav className="hidden md:flex items-center gap-1.5 p-1 rounded-xl bg-white/5 border border-white/5">
          {items.map((item) => (
            <button
              key={item.key}
              className={`flex items-center gap-2 rounded-lg px-4 py-2 text-[10px] font-black uppercase tracking-[0.18em] transition-all ${
                route === item.key
                  ? 'bg-brand-cyan/10 text-brand-cyan shadow-[inset_0_0_12px_rgba(0,242,254,0.1)] border border-brand-cyan/20'
                  : 'text-slate-400 hover:bg-white/5 hover:text-white border border-transparent'
              }`}
              onClick={() => onNavigate(item.key)}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </nav>

        {/* Action Group */}
        <div className="flex items-center gap-3">
          {/* Top-Right Mini Logo Status */}
          <motion.div 
            className="hidden lg:flex items-center gap-2 px-3 py-1.5 rounded-xl border border-white/10 bg-white/5 backdrop-blur-md"
            whileHover={{ borderColor: "rgba(0, 242, 254, 0.4)" }}
          >
            <div className="h-5 w-5 opacity-60">
              <img src="/logo.svg" alt="Status" className="h-full w-full object-contain" />
            </div>
            <div className="h-4 w-px bg-white/10" />
            <Badge label={`${reportCount} Evidence Blocks`} tone="info" className="bg-transparent border-none p-0 text-[10px]" />
          </motion.div>
          
          <div className="h-8 w-px bg-white/10 hidden sm:block mx-1" />
          
          <Button 
            variant={walletGate.isConnected ? 'ghost' : 'primary'} 
            onClick={onWalletAction} 
            disabled={walletGate.isConnecting}
            className={`min-w-[140px] flex items-center justify-center gap-2 ${walletGate.isConnected ? 'border-brand-cyan/20 text-brand-cyan' : ''}`}
          >
            <Wallet size={14} />
            <span className="text-[10px] font-black uppercase tracking-widest">{walletLabel}</span>
          </Button>
        </div>
      </div>
    </header>
  );
}
