import React from 'react';

export default function Badge({ label, tone = 'neutral', className = '' }) {
  const tones = {
    neutral: 'bg-white/10 text-slate-300 border border-white/15',
    info: 'bg-brand-cyan/10 text-brand-cyan border border-brand-cyan/30',
    success: 'bg-green-500/10 text-green-400 border border-green-500/30',
    warning: 'bg-yellow-500/10 text-yellow-300 border border-yellow-500/30',
    critical: 'bg-red-500/10 text-red-400 border border-red-500/30',
  };

  return (
    <span
      className={`inline-flex items-center rounded-md px-2 py-1 text-[10px] font-black uppercase tracking-wider ${
        tones[tone] ?? tones.neutral
      } ${className}`}
    >
      {label}
    </span>
  );
}
