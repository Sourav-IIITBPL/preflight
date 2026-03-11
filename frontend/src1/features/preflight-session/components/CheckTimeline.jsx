import React from 'react';
import { CheckCircle2, CircleDashed, CircleX, LoaderCircle } from 'lucide-react';

function getStatusIcon(status) {
  if (status === 'running') return <LoaderCircle className="h-4 w-4 animate-spin text-brand-cyan" />;
  if (status === 'done') return <CheckCircle2 className="h-4 w-4 text-green-400" />;
  if (status === 'error') return <CircleX className="h-4 w-4 text-red-400" />;
  return <CircleDashed className="h-4 w-4 text-slate-500" />;
}

function statusClass(status) {
  if (status === 'running') return 'border-brand-cyan/25 bg-brand-cyan/10 text-brand-cyan';
  if (status === 'done') return 'border-green-500/25 bg-green-500/10 text-green-400';
  if (status === 'error') return 'border-red-500/25 bg-red-500/10 text-red-400';
  return 'border-white/15 bg-white/5 text-slate-400';
}

export default function CheckTimeline({ timeline }) {
  return (
    <ol className="space-y-2.5">
      {timeline.map((step, index) => (
        <li key={step.id} className="rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2.5">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              {getStatusIcon(step.status)}
              <span className="text-xs font-bold text-white">{step.label}</span>
            </div>
            <span className={`rounded-md border px-2 py-0.5 text-[9px] font-black uppercase tracking-[0.14em] ${statusClass(step.status)}`}>
              {step.status}
            </span>
          </div>

          {step.message ? <p className="mt-1.5 text-[11px] leading-relaxed text-slate-400">{step.message}</p> : null}

          {index < timeline.length - 1 ? <div className="mt-2 h-px bg-white/5" /> : null}
        </li>
      ))}
    </ol>
  );
}
