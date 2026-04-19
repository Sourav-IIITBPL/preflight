import React from 'react';
import { motion } from 'framer-motion';
import { 
  Wallet, 
  RefreshCcw, 
  ShieldCheck, 
  Trophy, 
  Activity,
  Zap,
  Layers,
  Search
} from 'lucide-react';
import ReportGrid from './ReportGrid';
import Button from './ui/Button';
import Card from './ui/Card';
import RewardSummary from './RewardSummary';
import PortfolioEmptyState from './PortfolioEmptyState';

export default function PortfolioPage({ walletGate, portfolio, onWalletAction, onRefresh }) {
  const { isConnected, address, chainId } = walletGate;
  const { onchainReports, isLoading, summary } = portfolio;

  if (!isConnected) {
    return (
      <div className="flex min-h-[60vh] flex-col items-center justify-center text-center px-6">
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          className="glass-card p-12 rounded-[3rem] max-w-lg border-brand-cyan/20"
        >
          <div className="mx-auto mb-8 flex h-24 w-24 items-center justify-center rounded-full bg-brand-cyan/10 text-brand-cyan">
            <Wallet size={48} />
          </div>
          <h2 className="mb-4 text-4xl font-black text-white uppercase tracking-tight">Connect Wallet</h2>
          <p className="mb-10 text-slate-400 font-medium leading-relaxed">
            Connect your wallet to view your verified transactions and claim your PreFlight Risk Report NFTs.
          </p>
          <Button onClick={onWalletAction} className="w-full py-5 text-base font-black uppercase tracking-widest">
            Connect Now
          </Button>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="space-y-12 pb-20">
      {/* PORTFOLIO HEADER */}
      <header className="flex flex-col gap-8 md:flex-row md:items-end md:justify-between border-b border-white/5 pb-12">
        <div className="space-y-4">
           <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[10px] font-black uppercase tracking-widest">
              <Activity size={12} /> Live Status: Active
           </div>
           <h1 className="text-5xl md:text-6xl font-black text-white uppercase tracking-tighter">
             Your <span className="gradient-text">Verified</span> <br /> Transactions
           </h1>
           <div className="flex items-center gap-4 text-sm font-mono text-slate-500">
              <div className="flex items-center gap-2">
                 <div className="h-2 w-2 rounded-full bg-brand-cyan shadow-[0_0_8px_#00f2fe]" />
                 <span>Chain ID: {chainId || 'Unknown'}</span>
              </div>
              <div className="h-4 w-px bg-white/10" />
              <span>{address.slice(0, 6)}...{address.slice(-4)}</span>
           </div>
        </div>

        <div className="flex items-center gap-4">
           <Button variant="ghost" onClick={onRefresh} disabled={isLoading} className="border-white/10 text-white hover:bg-white/5">
              <RefreshCcw size={18} className={isLoading ? 'animate-spin' : ''} />
              {isLoading ? 'Syncing...' : 'Refresh'}
           </Button>
        </div>
      </header>

      {/* STATS OVERVIEW */}
      <section className="grid grid-cols-1 md:grid-cols-3 gap-6">
         {[
           { label: "Total Verified", value: summary.total, icon: <ShieldCheck className="text-emerald-400" /> },
           { label: "Security Points", value: summary.points, icon: <Trophy className="text-brand-cyan" /> },
           { label: "On-Chain Reports", value: summary.onchain, icon: <Layers className="text-purple-400" /> }
         ].map((stat, i) => (
           <Card key={i} className="glass-card p-8 border-white/5 group">
              <div className="flex justify-between items-start mb-4">
                 <div className="p-3 rounded-xl bg-white/5 text-brand-cyan group-hover:scale-110 transition-transform">
                    {stat.icon}
                 </div>
                 <div className="text-4xl font-black text-white">{stat.value}</div>
              </div>
              <div className="text-xs font-black uppercase tracking-[0.2em] text-slate-500">{stat.label}</div>
           </Card>
         ))}
      </section>

      {/* REWARD SUMMARY */}
      <RewardSummary summary={summary} />

      {/* REPORTS LIST */}
      <section className="space-y-8">
         <div className="flex items-center justify-between">
            <h2 className="text-3xl font-black text-white uppercase tracking-tight flex items-center gap-4">
               <Zap className="text-brand-cyan" /> Transaction Log
            </h2>
            <div className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white/5 border border-white/10 text-slate-400">
               <Search size={16} />
               <input type="text" placeholder="Search ID..." className="bg-transparent border-none outline-none text-xs w-24 md:w-48 font-medium" />
            </div>
         </div>

         {onchainReports.length > 0 ? (
           <ReportGrid items={onchainReports} isLoading={isLoading} />
         ) : (
           <PortfolioEmptyState onRefresh={onRefresh} />
         )}
      </section>
    </div>
  );
}
