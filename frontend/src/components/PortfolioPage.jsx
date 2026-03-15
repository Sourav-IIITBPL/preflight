import React from 'react';
import { motion } from 'framer-motion';
import { RefreshCw, Wallet, Shield, History, Award, CheckCircle2 } from 'lucide-react';
import PortfolioEmptyState from './PortfolioEmptyState';
import RewardSummary from './RewardSummary';
import ReportGrid from './ReportGrid';
import Button from './ui/Button';
import Card from './ui/Card';

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1
    }
  }
};

const itemVariants = {
  hidden: { y: 20, opacity: 0 },
  visible: {
    y: 0,
    opacity: 1,
    transition: {
      type: 'spring',
      stiffness: 100
    }
  }
};

export default function PortfolioPage({ walletGate, portfolio, onWalletAction, onRefresh }) {
  if (!walletGate.isConnected) {
    return <PortfolioEmptyState onConnect={walletGate.connectWallet} connectError={walletGate.error} />;
  }

  return (
    <motion.section 
      className="space-y-8"
      variants={containerVariants}
      initial="hidden"
      animate="visible"
    >
      <motion.div variants={itemVariants}>
        <Card className="p-6 md:p-8 glass-card border-l-4 border-l-brand-cyan relative overflow-hidden">
          <div className="absolute top-0 right-0 p-8 opacity-5">
            <Shield size={160} className="text-brand-cyan" />
          </div>
          
          <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="space-y-2">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-brand-cyan/10 border border-brand-cyan/20 text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan">
                <CheckCircle2 size={12} /> Live Dashboard
              </div>
              <h1 className="text-3xl font-black uppercase tracking-tight text-white md:text-4xl">Security Inventory</h1>
              <div className="flex items-center gap-3 text-sm text-slate-400 font-medium">
                <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white/5 border border-white/10">
                  <Wallet size={14} className="text-brand-cyan" />
                  <span className="font-mono text-slate-300">{walletGate.address.slice(0, 6)}...{walletGate.address.slice(-4)}</span>
                </div>
                <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-lg bg-brand-cyan/5 border border-brand-cyan/10 text-brand-cyan">
                  <Award size={14} />
                  <span>{portfolio.summary.points} XP</span>
                </div>
              </div>
            </div>

            <div className="flex flex-wrap gap-3">
              <Button variant="ghost" onClick={portfolio.clearLocalReports} disabled={!portfolio.localReports.length} className="px-5">
                Clear Cache
              </Button>
              <Button variant="outline" onClick={onWalletAction} className="px-5 border-red-500/20 text-red-400 hover:bg-red-500/10 hover:border-red-500/40">
                Disconnect
              </Button>
            </div>
          </div>
        </Card>
      </motion.div>

      <motion.div variants={itemVariants}>
        <RewardSummary summary={portfolio.summary} />
      </motion.div>

      <motion.div variants={itemVariants}>
        <Card className="p-6 md:p-8 glass-card border-t-1 border-white/5">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan">
                <RefreshCw size={14} className={portfolio.isLoading ? 'animate-spin' : ''} />
                Sync Protocol
              </div>
              <p className="max-w-2xl text-sm leading-relaxed text-slate-400 font-medium">
                The PreFlight dashboard automatically synchronizes with the RiskReport NFT contract to discover verified 
                transaction evidence associated with your account.
              </p>
            </div>
            <Button 
              variant="primary" 
              onClick={onRefresh} 
              disabled={portfolio.isLoading}
              className="px-8 shadow-[0_0_30px_rgba(0,242,254,0.2)]"
            >
              <RefreshCw size={16} className={portfolio.isLoading ? 'animate-spin' : ''} />
              {portfolio.isLoading ? 'Syncing...' : 'Force Sync'}
            </Button>
          </div>

          {portfolio.error && (
            <motion.div 
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              className="mt-6 rounded-2xl border border-amber-500/20 bg-amber-500/5 p-4 text-sm text-amber-200/80 flex items-center gap-3"
            >
              <History size={18} className="text-amber-500 shrink-0" />
              {portfolio.error}
            </motion.div>
          )}
        </Card>
      </motion.div>

      <motion.div variants={itemVariants} className="space-y-12 pb-12">
        <ReportGrid
          title="On-chain Evidence (NFTs)"
          reports={portfolio.onchainReports}
          emptyText="No on-chain report NFTs discovered. Intercept a transaction via the extension to mint your first report."
        />

        <div className="h-px bg-gradient-to-r from-transparent via-white/10 to-transparent" />

        <ReportGrid
          title="Session Cache (Local)"
          reports={portfolio.localReports}
          emptyText="No local sessions found. Session data is captured automatically when using the PreFlight extension."
        />
      </motion.div>
    </motion.section>
  );
}
