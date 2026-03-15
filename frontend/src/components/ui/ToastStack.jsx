import React from 'react';
import { AnimatePresence, motion } from 'framer-motion';

export default function ToastStack({ items }) {
  return (
    <div className="fixed right-4 top-4 z-[200] w-[320px] space-y-2">
      <AnimatePresence>
        {items.map((toast) => (
          <motion.div
            key={toast.id}
            initial={{ opacity: 0, y: -12, x: 12 }}
            animate={{ opacity: 1, y: 0, x: 0 }}
            exit={{ opacity: 0, y: -10, x: 10 }}
            className="rounded-2xl border border-white/10 bg-[#101010]/90 px-4 py-3 backdrop-blur-xl"
          >
            <div className="text-sm font-bold text-white">{toast.title}</div>
            {toast.message ? <div className="mt-1 text-xs text-slate-400">{toast.message}</div> : null}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
