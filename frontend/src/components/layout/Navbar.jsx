import React from 'react';
import { motion } from 'framer-motion';
import { APP_NAME, NETWORK_LABEL, ROUTES } from '../../constants';
import Button from '../ui/Button';
import Badge from '../ui/Badge';
import Logo from '../ui/Logo';
import { Wallet, History, Info, Menu, ShieldCheck } from 'lucide-react';

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
    <header className="sticky top-0 z-50 glass-nav">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 md:px-6">
        {/* Brand Group */}
        <motion.button 
          className="flex items-center gap-3 group" 
          onClick={() => onNavigate(ROUTES.HOME)}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
        >
          <Logo className="h-12 w-12" animated={true} />
          <div className="hidden sm:block text-left">
            <div className="text-xl font-black uppercase tracking-[0.2em] text-white leading-none">{APP_NAME}</div>
            <div className="mt-1 text-[8px] font-bold uppercase tracking-[0.3em] text-brand-cyan">{NETWORK_LABEL}</div>
          </div>
        </motion.button>

        {/* Navigation Group */}
        <nav className="hidden md:flex items-center gap-2 p-1 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md">
          {items.map((item) => (
            <button
              key={item.key}
              className={`flex items-center gap-2 rounded-xl px-5 py-2.5 text-[10px] font-black uppercase tracking-[0.2em] transition-all duration-300 ${
                route === item.key
                  ? 'bg-brand-cyan/20 text-brand-cyan border border-brand-cyan/30 shadow-[0_0_15px_rgba(0,242,254,0.2)]'
                  : 'text-slate-400 hover:bg-white/10 hover:text-white border border-transparent'
              }`}
              onClick={() => onNavigate(item.key)}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </nav>

        {/* Action Group */}
        <div className="flex items-center gap-4">
          {/* Verified Transaction Count */}
          <motion.div 
            className="hidden lg:flex items-center gap-3 px-4 py-2 rounded-xl border border-emerald-500/20 bg-emerald-500/5 backdrop-blur-md"
            whileHover={{ borderColor: "rgba(16, 185, 129, 0.4)" }}
          >
            <ShieldCheck size={14} className="text-emerald-400" />
            <div className="h-4 w-px bg-emerald-500/10" />
            <span className="text-[10px] font-black uppercase tracking-widest text-emerald-400">
              {reportCount} Verified Transactions
            </span>
          </motion.div>
          
          <Button 
            variant={walletGate.isConnected ? 'ghost' : 'primary'} 
            onClick={onWalletAction} 
            disabled={walletGate.isConnecting}
            className={`flex items-center justify-center gap-2 px-6 py-3 border-brand-cyan/20 ${walletGate.isConnected ? 'text-brand-cyan' : ''}`}
          >
            <Wallet size={14} />
            <span className="text-[10px] font-black uppercase tracking-widest">{walletLabel}</span>
          </Button>
        </div>
      </div>
    </header>
  );
}
