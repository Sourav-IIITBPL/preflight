import React from 'react';
import { ShieldCheck } from 'lucide-react';

function normalizeEntries(data) {
  if (!data || typeof data !== 'object') return [];

  return Object.entries(data).map(([key, value]) => {
    const formatted =
      typeof value === 'boolean' ? (value ? 'true' : 'false') : typeof value === 'number' ? String(value) : String(value ?? 'n/a');

    const tone = typeof value === 'boolean' && value ? 'warn' : 'ok';

    return { key, formatted, tone };
  });
}

function FlagRow({ label, value, tone = 'ok' }) {
  const toneClass =
    tone === 'warn'
      ? 'bg-yellow-500/10 text-yellow-300 border-yellow-500/20'
      : 'bg-green-500/10 text-green-400 border-green-500/20';

  return (
    <div className="flex items-center justify-between p-3 rounded-lg bg-white/[0.02] border border-white/5">
      <div className="flex flex-col">
        <span className="text-xs font-bold text-white uppercase tracking-wide">{label}</span>
        <span className="text-[10px] text-gray-500">{value}</span>
      </div>
      <span className={`text-[10px] px-2 py-1 rounded font-bold border uppercase ${toneClass}`}>{tone === 'warn' ? 'Warn' : 'Pass'}</span>
    </div>
  );
}

export default function RiskBreakdown({ report }) {
  const traceEntries = normalizeEntries(report?.offchain?.trace);
  const economicEntries = normalizeEntries(report?.offchain?.economic);
  const onchainChecks = report?.onchain?.checks ?? [];

  return (
    <div className="space-y-4">
      <div>
        <h4 className="text-[10px] font-black uppercase tracking-widest text-gray-500 mb-3">Trace & Economic Flags</h4>
        <div className="grid gap-2 md:grid-cols-2">
          {[...traceEntries.slice(0, 4), ...economicEntries.slice(0, 4)].map((item) => (
            <FlagRow key={`${item.key}_${item.formatted}`} label={item.key} value={item.formatted} tone={item.tone} />
          ))}
        </div>
      </div>

      <div>
        <h4 className="text-[10px] font-black uppercase tracking-widest text-gray-500 mb-3">On-chain Check Status</h4>
        <div className="grid gap-2 md:grid-cols-2">
          {onchainChecks.length ? (
            onchainChecks.map((check) => (
              <div key={check.id} className="rounded-lg bg-white/[0.02] border border-white/5 p-3">
                <div className="flex items-center gap-2 text-[10px] text-brand-cyan uppercase tracking-wide mb-1">
                  <ShieldCheck size={12} /> {check.id}
                </div>
                <div className="text-xs text-white font-bold">{check.label}</div>
                <div className="text-[10px] text-yellow-300 uppercase tracking-wide mt-1">{check.status}</div>
              </div>
            ))
          ) : (
            <p className="text-xs text-slate-500">No on-chain checks returned.</p>
          )}
        </div>
      </div>
    </div>
  );
}
