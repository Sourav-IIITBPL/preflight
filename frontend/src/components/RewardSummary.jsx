import React from 'react';
import Card from './ui/Card';

export default function RewardSummary({ summary }) {
  const items = [
    { label: 'Total reports', value: summary.total, tone: 'text-white' },
    { label: 'On-chain synced', value: summary.onchain, tone: 'text-brand-cyan' },
    { label: 'Local cache', value: summary.local, tone: 'text-slate-200' },
    { label: 'Reward points (preview)', value: summary.points, tone: 'text-emerald-300' },
  ];

  return (
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      {items.map((item) => (
        <Card key={item.label} className="p-5 hover-reveal">
          <div className="text-[10px] font-black uppercase tracking-[0.2em] text-slate-500">{item.label}</div>
          <div className={`mt-3 text-4xl font-black ${item.tone}`}>{item.value}</div>
        </Card>
      ))}
    </section>
  );
}
