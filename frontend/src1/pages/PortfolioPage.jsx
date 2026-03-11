import React from 'react';
import { Wallet } from 'lucide-react';
import PortfolioEmptyState from '../features/portfolio/components/PortfolioEmptyState';
import ReportNftGrid from '../features/portfolio/components/ReportNftGrid';
import RewardSummary from '../features/portfolio/components/RewardSummary';
import Button from '../shared/ui/Button';
import Card from '../shared/ui/Card';

export default function PortfolioPage({ walletGate, mintedReports, clearReports }) {
  if (!walletGate.isConnected) {
    return <PortfolioEmptyState onConnect={walletGate.connectWallet} connectError={walletGate.error} />;
  }

  return (
    <section className="space-y-6">
      <Card className="p-5 md:p-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan">Portfolio Dashboard</p>
            <h1 className="text-2xl font-black uppercase tracking-[0.1em] text-white mt-1">My PreFlight Reports & Rewards</h1>
            <p className="mt-3 text-xs text-slate-400 flex items-center gap-2">
              <Wallet size={14} className="text-brand-cyan" />
              Connected wallet: <span className="font-mono text-slate-200">{walletGate.address}</span>
            </p>
          </div>

          <Button variant="ghost" onClick={clearReports} disabled={!mintedReports.length}>
            Clear Local Report Cache
          </Button>
        </div>
      </Card>

      <RewardSummary reports={mintedReports} />
      <ReportNftGrid reports={mintedReports} />
    </section>
  );
}
