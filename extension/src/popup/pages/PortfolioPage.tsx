import React from 'react';
import { motion } from 'framer-motion';
import { ExternalLink, FolderClock, Shield, AlertTriangle, CheckCircle } from 'lucide-react';
import type { StoredReport } from '../../shared/types';

interface PortfolioPageProps {
  reports: StoredReport[];
  onOpenWebsite(): void;
}

export default function PortfolioPage({ reports, onOpenWebsite }: PortfolioPageProps) {
  if (!reports.length) {
    return (
      <motion.section 
        className="glass-card p-8 text-center"
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
      >
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-2xl border border-brand-cyan/25 bg-brand-cyan/10 text-brand-cyan shadow-[0_0_20px_rgba(0,242,254,0.15)]">
          <FolderClock size={28} />
        </div>
        <h2 className="mt-6 text-xl font-black uppercase tracking-[0.1em] text-white">History Empty</h2>
        <p className="mt-3 text-[11px] leading-relaxed text-slate-500">
          Intercepted DEX transactions will appear here as local security evidence.
        </p>
        <motion.button 
          className="btn-ghost mt-8 w-full" 
          onClick={onOpenWebsite}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
        >
          <ExternalLink size={14} /> Global Portfolio
        </motion.button>
      </motion.section>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between px-1">
        <div className="text-[9px] font-black uppercase tracking-[0.2em] text-slate-500">Local Evidence ({reports.length})</div>
      </div>
      
      <div className="space-y-3">
        {reports.map((report, i) => (
          <motion.section 
            key={report.id} 
            className="glass-card p-4 relative overflow-hidden group"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.05 }}
            whileHover={{ borderLeftColor: 'rgba(0, 242, 254, 0.6)' }}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-[8px] font-black uppercase tracking-[0.15em] text-brand-cyan/70">{report.protocol}</div>
                <div className="mt-1 text-sm font-black uppercase tracking-[0.05em] text-white group-hover:text-brand-cyan transition-colors">{report.operationType}</div>
              </div>
              
              <div className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[8px] font-black uppercase tracking-[0.1em] 
                ${report.riskLevel === 'CRITICAL' 
                  ? 'border-red-500/30 bg-red-500/10 text-red-400' 
                  : report.riskLevel === 'WARNING' 
                    ? 'border-amber-500/30 bg-amber-500/10 text-amber-300' 
                    : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'}`}
              >
                {report.riskLevel === 'CRITICAL' && <AlertTriangle size={10} />}
                {report.riskLevel === 'WARNING' && <Shield size={10} />}
                {report.riskLevel === 'SAFE' && <CheckCircle size={10} />}
                {report.riskLevel}
              </div>
            </div>
            
            <p className="mt-3 text-[11px] leading-relaxed text-slate-400 line-clamp-2">{report.summary}</p>
            
            <div className="mt-4 flex items-center justify-between border-t border-white/5 pt-3 text-[9px] font-medium text-slate-500 uppercase tracking-tighter">
              <span>{new Date(report.createdAt).toLocaleDateString()}</span>
              <span className="opacity-50 truncate max-w-[140px]">{report.target}</span>
            </div>
          </motion.section>
        ))}
      </div>
      
      <motion.button 
        className="btn-ghost w-full mt-6 opacity-60 hover:opacity-100" 
        onClick={onOpenWebsite}
        whileHover={{ scale: 1.01 }}
      >
        <ExternalLink size={12} /> View Full History
      </motion.button>
    </div>
  );
}
