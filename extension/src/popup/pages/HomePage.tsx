import React from 'react';
import { motion } from 'framer-motion';
import { Activity, ExternalLink, ShieldCheck, Globe, Zap, AlertCircle } from 'lucide-react';
import type { SiteSession } from '../../shared/types';

interface HomePageProps {
  activeSite?: SiteSession;
  onActivate(): void;
  onOpenWebsite(): void;
}

export default function HomePage({ activeSite, onActivate, onOpenWebsite }: HomePageProps) {
  return (
    <div className="space-y-5">
      {/* Hero Section */}
      <motion.section 
        className="glass-card p-5 relative overflow-hidden"
        initial={{ y: 10, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
      >
        <div className="absolute top-0 right-0 p-3 opacity-10">
          <Globe size={64} className="text-brand-cyan" />
        </div>
        
        <div className="relative z-10">
          <div className="flex items-center gap-2 text-[9px] font-black uppercase tracking-[0.2em] text-brand-cyan/80">
            <Zap size={10} /> Live Detection
          </div>
          <h2 className="mt-2 text-2xl font-black uppercase tracking-[0.08em] text-white">
            {activeSite?.protocol || 'System Idle'}
          </h2>
          <div className="mt-3 flex items-center gap-2 text-xs text-slate-400">
            {activeSite ? (
              <span className="inline-flex items-center gap-1.5 text-brand-cyan">
                <span className="h-1.5 w-1.5 rounded-full bg-brand-cyan animate-pulse" />
                {activeSite.host}
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5">
                <AlertCircle size={12} /> No supported DEX detected
              </span>
            )}
          </div>
          <p className="mt-4 text-[11px] leading-relaxed text-slate-400">
            {activeSite
              ? `PreFlight is ready to intercept. Activate to start real-time calldata decoding and security checks.`
              : 'Open Camelot or SaucerSwap in the active tab to enable PreFlight security interception.'}
          </p>
          <div className="mt-6 flex flex-col gap-2">
            <motion.button 
              className="btn-primary w-full py-3.5" 
              onClick={onActivate}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              disabled={!activeSite}
            >
              <ShieldCheck size={14} /> {activeSite?.activated ? 'Re-activate Security' : 'Activate PreFlight'}
            </motion.button>
            <motion.button 
              className="btn-ghost w-full py-3.5" 
              onClick={onOpenWebsite}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
            >
              <ExternalLink size={14} /> Open Dashboard
            </motion.button>
          </div>
        </div>
      </motion.section>

      {/* DEX Support Info */}
      <div className="grid gap-3">
        {[
          {
            title: 'Camelot',
            chain: 'Arbitrum One',
            text: 'Full V2/V3 calldata decoding active.',
          },
          {
            title: 'SaucerSwap',
            chain: 'Hedera Mainnet',
            text: 'Protocol adapter compatibility active.',
          },
        ].map((item, i) => (
          <motion.div 
            key={item.title} 
            className="glass-card p-4 border-l-0 border-t-1 border-white/5"
            initial={{ y: 10, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ delay: 0.1 * (i + 1) }}
          >
            <div className="flex justify-between items-start">
              <div>
                <div className="text-[8px] font-black uppercase tracking-[0.18em] text-brand-cyan/60">{item.chain}</div>
                <div className="mt-1 text-sm font-black uppercase tracking-[0.08em] text-white">{item.title}</div>
              </div>
              <Activity size={12} className="text-brand-cyan/40" />
            </div>
            <p className="mt-2 text-[10px] leading-relaxed text-slate-500">{item.text}</p>
          </motion.div>
        ))}
      </div>

      {/* Workflow Indicator */}
      <motion.section 
        className="glass-card p-4 bg-brand-cyan/5 border-brand-cyan/20"
        initial={{ y: 10, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ delay: 0.3 }}
      >
        <div className="flex items-center gap-2 text-[9px] font-black uppercase tracking-[0.2em] text-brand-cyan">
          <Activity size={12} /> Security Loop
        </div>
        <div className="mt-3 space-y-2 text-[10px] text-slate-400">
          <div className="flex gap-2">
            <span className="text-brand-cyan">01</span>
            <span>Intercepts transaction calldata</span>
          </div>
          <div className="flex gap-2">
            <span className="text-brand-cyan">02</span>
            <span>Runs CRE simulation & Guard reads</span>
          </div>
          <div className="flex gap-2">
            <span className="text-brand-cyan">03</span>
            <span>Renders verdict before wallet signature</span>
          </div>
        </div>
      </motion.section>
    </div>
  );
}
