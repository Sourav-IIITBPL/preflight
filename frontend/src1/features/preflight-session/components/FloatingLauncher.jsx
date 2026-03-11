import React from 'react';
import { motion } from 'framer-motion';
import { Shield, PanelRightOpen } from 'lucide-react';

export default function FloatingLauncher({ hidden = false, disabled = false, onClick }) {
  if (hidden) return null;

  return (
    <motion.button
      type="button"
      initial={{ opacity: 0, scale: 0.85, y: 12 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      whileHover={disabled ? {} : { scale: 1.03 }}
      whileTap={disabled ? {} : { scale: 0.98 }}
      onClick={onClick}
      disabled={disabled}
      className="fixed bottom-7 right-7 z-[140] inline-flex items-center gap-2 rounded-full border border-brand-cyan/30 bg-black/70 px-5 py-3 text-sm font-black uppercase tracking-[0.17em] text-brand-cyan shadow-[0_0_30px_rgba(0,242,254,0.22)] backdrop-blur disabled:cursor-not-allowed disabled:opacity-60"
    >
      <span className="relative inline-flex h-8 w-8 items-center justify-center rounded-full bg-brand-cyan text-black">
        <Shield size={16} fill="currentColor" />
        <span className="absolute -bottom-1 -right-1 rounded-full bg-black px-1 text-[8px] text-brand-cyan">v1</span>
      </span>
      PreFlight
      <PanelRightOpen size={14} />
      <span className="pointer-events-none absolute inset-0 -z-10 rounded-full bg-brand-cyan/10 blur-xl" />
    </motion.button>
  );
}
