import React from 'react';
import { ShieldAlert, Wallet } from 'lucide-react';
import Button from './ui/Button';
import Card from './ui/Card';

export default function PortfolioEmptyState({ onConnect, connectError }) {
  return (
    <Card className="mx-auto max-w-3xl p-8 text-center md:p-10">
      <div className="space-y-6">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-2xl border border-brand-cyan/30 bg-brand-cyan/10 text-brand-cyan">
          <Wallet size={26} />
        </div>
        <div>
          <p className="text-[10px] font-black uppercase tracking-[0.24em] text-brand-cyan">Portfolio Locked</p>
          <h1 className="mt-2 text-2xl font-black uppercase tracking-[0.12em] text-white">My PreFlight Reports & Rewards</h1>
          <p className="mx-auto mt-3 max-w-xl text-sm leading-relaxed text-slate-400">
            Connect wallet to view on-chain RiskReport NFTs, locally cached previews, and the same report history that will later surface inside the PreFlight extension.
          </p>
        </div>
        <Button onClick={onConnect} className="px-8 py-3">Connect Wallet</Button>
        {connectError ? (
          <div className="inline-flex items-center gap-2 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs text-red-200">
            <ShieldAlert size={14} />
            {connectError}
          </div>
        ) : null}
      </div>
    </Card>
  );
}
