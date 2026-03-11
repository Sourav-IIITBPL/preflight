import React, { useMemo } from 'react';
import Card from '../../../shared/ui/Card';

function calcRewardPoints(reports) {
  return reports.reduce((acc, item) => {
    const base = item.riskLevel === 'CRITICAL' ? 30 : item.riskLevel === 'WARNING' ? 20 : 10;
    return acc + base;
  }, 0);
}

export default function RewardSummary({ reports }) {
  const stats = useMemo(() => {
    const total = reports.length;
    const points = calcRewardPoints(reports);
    const safe = reports.filter((item) => item.riskLevel === 'SAFE').length;

    return { total, points, safe };
  }, [reports]);

  return (
    <section className="grid gap-3 md:grid-cols-3">
      <Card className="p-5 hover-reveal">
        <div className="text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black">Total reports</div>
        <div className="mt-3 text-4xl font-black text-white">{stats.total}</div>
      </Card>

      <Card className="p-5 hover-reveal">
        <div className="text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black">Reward points (preview)</div>
        <div className="mt-3 text-4xl font-black text-brand-cyan">{stats.points}</div>
      </Card>

      <Card className="p-5 hover-reveal">
        <div className="text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black">Safe intents</div>
        <div className="mt-3 text-4xl font-black text-green-400">{stats.safe}</div>
      </Card>
    </section>
  );
}
