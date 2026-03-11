import React from 'react';
import { FileText } from 'lucide-react';

export default function MintReportButton({ onClick, status = 'idle' }) {
  const label = status === 'pending' ? 'Minting Report...' : 'Mint On-Chain Report';

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={status === 'pending'}
      className="inline-flex items-center justify-center gap-2 rounded-xl bg-brand-cyan px-4 py-2 text-[11px] font-black uppercase tracking-wider text-black transition-all hover:brightness-110 hover:shadow-[0_0_28px_rgba(0,242,254,0.35)] disabled:cursor-not-allowed disabled:opacity-70"
    >
      <FileText size={14} />
      {label}
    </button>
  );
}
