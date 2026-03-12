import React from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Globe, Layers2, X } from 'lucide-react';
import { SUPPORTED_DEXES } from '../../../shared/constants/app';

export default function DexSelectorModal({ isOpen, onClose, onChoose }) {
  return (
    <AnimatePresence>
      {isOpen ? (
        <>
          <motion.div
            className="fixed inset-0 z-[180] bg-black/70 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          <motion.div
            className="fixed left-1/2 top-1/2 z-[190] w-[min(680px,calc(100vw-24px))] -translate-x-1/2 -translate-y-1/2 rounded-3xl glass-card border border-brand-cyan/20 p-5 md:p-7"
            initial={{ opacity: 0, scale: 0.96, y: 18 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.97, y: 12 }}
          >
            <div className="flex items-start justify-between gap-3 border-b border-white/10 pb-4">
              <div>
                <p className="text-[10px] font-black uppercase tracking-[0.24em] text-brand-cyan">Launch Runtime</p>
                <h3 className="mt-1 text-2xl font-black uppercase tracking-[0.1em] text-white">Choose Your DEX</h3>
                <p className="mt-2 text-sm text-slate-400">Select a supported DEX. A dedicated DEX page will open inside PreFlight.</p>
              </div>
              <button
                className="rounded-lg border border-white/10 p-2 text-slate-400 hover:border-white/30 hover:text-white"
                onClick={onClose}
              >
                <X size={16} />
              </button>
            </div>

            <div className="mt-5 grid gap-3 md:grid-cols-2">
              {SUPPORTED_DEXES.map((dex) => (
                <button
                  key={dex.id}
                  onClick={() => onChoose(dex.id)}
                  className="text-left rounded-2xl border border-white/10 bg-white/[0.03] p-4 transition hover:border-brand-cyan/40 hover:bg-white/[0.05]"
                >
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <div className="h-9 w-9 rounded-lg border border-brand-cyan/30 bg-brand-cyan/10 grid place-items-center text-brand-cyan">
                        <Layers2 size={16} />
                      </div>
                      <div>
                        <div className="text-sm font-black uppercase tracking-[0.12em] text-white">{dex.name}</div>
                        <div className="text-[10px] uppercase tracking-[0.14em] text-brand-cyan">{dex.tag}</div>
                      </div>
                    </div>
                    <Globe size={16} className="text-slate-500" />
                  </div>

                  <div className="mt-3 rounded-lg border border-white/10 bg-black/30 p-2 text-[11px] text-slate-400 break-all">
                    {dex.url}
                  </div>
                </button>
              ))}
            </div>
          </motion.div>
        </>
      ) : null}
    </AnimatePresence>
  );
}
