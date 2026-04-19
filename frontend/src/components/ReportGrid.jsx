import React from 'react';
import { motion } from 'framer-motion';
import { ExternalLink, ShieldCheck, AlertTriangle, CheckCircle, Info, Activity } from 'lucide-react';
import Card from './ui/Card';
import Badge from './ui/Badge';

function riskTone(level) {
  if (level === 'CRITICAL') return 'critical';
  if (level === 'WARNING') return 'warning';
  return 'success';
}

const gridVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05
    }
  }
};

const cardVariants = {
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

export default function ReportGrid({ items = [], isLoading }) {
  return (
    <section className="space-y-6">
      {!items.length ? (
        <motion.div 
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
        >
          <Card className="p-20 text-center glass-card border-dashed border-white/10 rounded-[3rem]">
            <div className="mx-auto w-16 h-16 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center mb-6 text-slate-500">
              <Info size={32} />
            </div>
            <h3 className="text-xl font-bold text-white mb-2 uppercase">No Transactions Found</h3>
            <p className="text-sm text-slate-500 max-w-xs mx-auto leading-relaxed">Your verified transaction history will appear here once you start using the PreFlight extension.</p>
          </Card>
        </motion.div>
      ) : (
        <motion.div 
          className="grid gap-6 md:grid-cols-2 lg:grid-cols-3"
          variants={gridVariants}
          initial="hidden"
          animate="visible"
        >
          {items.map((item) => (
            <motion.div key={item.id} variants={cardVariants}>
              <Card className="h-full flex flex-col space-y-5 p-6 glass-card group relative overflow-hidden rounded-[2.5rem]">
                {/* Visual Accent */}
                <div className={`absolute top-0 right-0 w-24 h-24 -mr-8 -mt-8 rounded-full blur-3xl opacity-10 transition-opacity group-hover:opacity-20 
                  ${item.riskLevel === 'CRITICAL' ? 'bg-red-500' : item.riskLevel === 'WARNING' ? 'bg-amber-500' : 'bg-emerald-500'}`} 
                />

                <div className="flex items-start justify-between gap-3 relative z-10">
                  <div className="space-y-1">
                    <div className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-500 group-hover:text-brand-cyan transition-colors">
                      {item.source === 'onchain' ? 'On-chain Protocol' : 'Local Session'}
                    </div>
                    <div className="text-2xl font-black text-white tracking-tight leading-none group-hover:translate-x-1 transition-transform uppercase">
                      {item.source === 'onchain' ? `#${item.tokenId}` : 'PREVIEW'}
                    </div>
                  </div>
                  <Badge label={item.riskLevel} tone={riskTone(item.riskLevel)} className="px-3 py-1 text-[9px] uppercase font-black tracking-widest rounded-lg" />
                </div>

                <div className="flex-1 space-y-4 relative z-10">
                  <div className="rounded-[1.5rem] border border-white/10 bg-black/40 p-5 text-xs text-slate-300 backdrop-blur-sm group-hover:border-brand-cyan/20 transition-all">
                    <div className="flex items-center gap-2 mb-4">
                      <div className={`p-2 rounded-xl ${item.riskLevel === 'CRITICAL' ? 'bg-red-500/10 text-red-400' : item.riskLevel === 'WARNING' ? 'bg-amber-500/10 text-amber-400' : 'bg-emerald-500/10 text-emerald-400'}`}>
                        {item.riskLevel === 'CRITICAL' ? <AlertTriangle size={16} /> : item.riskLevel === 'WARNING' ? <ShieldCheck size={16} /> : <CheckCircle size={16} />}
                      </div>
                      <span className="font-black uppercase tracking-[0.1em] text-white text-xs">{item.intentType}</span>
                    </div>
                    
                    <div className="space-y-4 font-medium">
                      <div className="space-y-1.5">
                        <div className="text-[8px] uppercase tracking-widest text-slate-500 font-black">Target Address</div>
                        <p className="break-all text-slate-300 font-mono text-[10px] bg-white/5 p-2 rounded-lg border border-white/5">{item.target || item.targetUrl || 'Detecting...'}</p>
                      </div>
                      
                      <div className="grid grid-cols-2 gap-3 text-[9px] uppercase tracking-widest text-slate-400">
                        <div className="space-y-1">
                          <div className="text-[8px] tracking-widest text-slate-500 font-black uppercase">Timestamp</div>
                          <div className="text-slate-300 font-bold">{new Date(item.mintedAt).toLocaleDateString()}</div>
                        </div>
                        <div className="space-y-1">
                          <div className="text-[8px] tracking-widest text-slate-500 font-black uppercase">Status</div>
                          <div className="text-brand-cyan font-bold">{item.status}</div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-between px-1">
                    <div className="space-y-2 flex-1">
                      <div className="text-[8px] font-black uppercase tracking-[0.25em] text-slate-500">Risk Severity Score</div>
                      <div className="flex items-center gap-3">
                        <div className="flex-1 h-1.5 bg-white/5 rounded-full overflow-hidden">
                          <motion.div 
                            initial={{ width: 0 }}
                            animate={{ width: `${item.riskScore}%` }}
                            className={`h-full ${item.riskLevel === 'CRITICAL' ? 'bg-red-500' : item.riskLevel === 'WARNING' ? 'bg-amber-500' : 'bg-emerald-500'}`}
                          />
                        </div>
                        <span className="text-sm font-black text-white tabular-nums">{item.riskScore}</span>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="pt-4 flex items-center justify-between relative z-10 border-t border-white/5">
                  <a
                    className="inline-flex items-center gap-2 text-[10px] font-black uppercase tracking-[0.25em] text-brand-cyan hover:text-white transition-all hover:gap-3"
                    href={item.txHash ? `https://arbiscan.io/tx/${item.txHash}` : '#'}
                    target="_blank"
                    rel="noreferrer"
                    onClick={(event) => {
                      if (!item.txHash || String(item.txHash).startsWith('sim_')) {
                        event.preventDefault();
                      }
                    }}
                  >
                    View Evidence <ExternalLink size={12} />
                  </a>
                  
                  {item.amount && (
                    <div className="text-[10px] font-black text-slate-400 bg-white/5 px-3 py-1 rounded-full border border-white/5">
                      {item.amount} <span className="text-[8px] opacity-60 ml-0.5">UNIT</span>
                    </div>
                  )}
                </div>
              </Card>
            </motion.div>
          ))}
        </motion.div>
      )}
    </section>
  );
}
