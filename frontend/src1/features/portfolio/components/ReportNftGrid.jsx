import React from 'react';
import { ExternalLink, ShieldCheck } from 'lucide-react';
import Card from '../../../shared/ui/Card';
import Badge from '../../../shared/ui/Badge';

function riskTone(level) {
  if (level === 'CRITICAL') return 'critical';
  if (level === 'WARNING') return 'warning';
  return 'success';
}

export default function ReportNftGrid({ reports }) {
  if (!reports.length) {
    return (
      <Card className="p-6 text-sm text-slate-400">
        No report NFTs yet. Go to Launchpad, run PreFlight checks, and mint your first report.
      </Card>
    );
  }

  return (
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {reports.map((item) => (
        <Card key={item.id} className="space-y-4 p-5 hover-reveal">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black">Report NFT</div>
              <div className="text-xl font-black text-white">#{item.tokenId}</div>
            </div>
            <Badge label={item.riskLevel} tone={riskTone(item.riskLevel)} />
          </div>

          <div className="rounded-xl border border-white/10 bg-black/30 p-3 text-xs text-slate-300">
            <div className="flex items-center gap-2">
              <ShieldCheck size={14} className="text-brand-cyan" />
              <span className="font-bold text-white uppercase tracking-wide">{item.intentType}</span>
            </div>
            <p className="mt-2 text-slate-400 break-all">{item.targetUrl || 'No target URL captured'}</p>
            <p className="mt-2 text-[11px] text-slate-500">Minted: {new Date(item.mintedAt).toLocaleString()}</p>
          </div>

          <div className="flex items-center justify-between text-xs">
            <span className="text-slate-500 uppercase tracking-wider">Risk score</span>
            <span className="font-black text-white text-lg leading-none">{item.riskScore}</span>
          </div>

          <a
            className="inline-flex items-center gap-2 text-xs text-brand-cyan hover:underline"
            href={item.txHash ? `https://arbiscan.io/tx/${item.txHash}` : '#'}
            target="_blank"
            rel="noreferrer"
            onClick={(event) => {
              if (!item.txHash || String(item.txHash).startsWith('sim_')) {
                event.preventDefault();
              }
            }}
          >
            View mint transaction <ExternalLink size={12} />
          </a>
        </Card>
      ))}
    </section>
  );
}
