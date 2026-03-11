import React from 'react';
import { AnimatePresence, motion } from 'framer-motion';

export default function ToastStack({ items }) {
  return (
    <div className="fixed top-4 right-4 z-[250] space-y-2 w-[320px]">
      <AnimatePresence>
        {items.map((toast) => (
          <motion.div
            key={toast.id}
            initial={{ opacity: 0, y: -12, x: 12 }}
            animate={{ opacity: 1, y: 0, x: 0 }}
            exit={{ opacity: 0, y: -10, x: 10 }}
            className="rounded-xl border border-white/10 bg-[#101010]/90 backdrop-blur px-4 py-3 text-sm"
          >
            <div className="font-bold text-white">{toast.title}</div>
            {toast.message ? <div className="text-xs text-slate-400 mt-1">{toast.message}</div> : null}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
