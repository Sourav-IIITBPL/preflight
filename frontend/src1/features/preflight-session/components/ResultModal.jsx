import React from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { AlertTriangle, Clock3, X } from 'lucide-react';
import RiskShield from '../../reports/components/RiskShield';
import RiskBreakdown from '../../reports/components/RiskBreakdown';
import MintReportButton from '../../reports/components/MintReportButton';
import Badge from '../../../shared/ui/Badge';

function toneFromRisk(level) {
  if (level === 'CRITICAL') return 'critical';
  if (level === 'WARNING') return 'warning';
  return 'success';
}

export default function ResultModal({ isOpen, onClose, report, secondsLeft, mintState, onMint, onRecheck }) {
  const riskLevel = report?.final?.riskLevel ?? 'SAFE';

  return (
    <AnimatePresence>
      {isOpen ? (
        <>
          <motion.div
            className="fixed inset-0 z-[165] bg-black/70 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          <motion.div
            className="fixed left-1/2 top-1/2 z-[170] w-[min(980px,calc(100vw-18px))] -translate-x-1/2 -translate-y-1/2 glass-card rounded-3xl border border-brand-cyan/20 p-4 shadow-[0_0_60px_rgba(0,0,0,0.65)] md:p-6"
            initial={{ opacity: 0, y: 24, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 16, scale: 0.98 }}
          >
            <div className="mb-4 flex items-start justify-between gap-3 border-b border-white/10 pb-3">
              <div>
                <p className="text-[10px] font-black uppercase tracking-[0.22em] text-brand-cyan">PreFlight Report</p>
                <h3 className="text-xl font-black uppercase tracking-[0.09em] text-white">Off-chain + On-chain Summary</h3>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-white/10 p-2 text-slate-400 transition hover:border-white/30 hover:text-white"
              >
                <X size={16} />
              </button>
            </div>

            {!report ? (
              <div className="rounded-xl border border-white/10 bg-white/[0.03] p-6 text-sm text-slate-400">Run checks first to generate a report.</div>
            ) : (
              <div className="space-y-5">
                <div className="grid gap-4 md:grid-cols-[280px_1fr]">
                  <RiskShield score={report.final.riskScore} riskLevel={report.final.riskLevel} />

                  <div className="space-y-3 rounded-2xl border border-white/10 bg-white/[0.02] p-4">
                    <div className="flex items-center justify-between">
                      <div className="text-[10px] font-black uppercase tracking-[0.15em] text-slate-400">Final Verdict</div>
                      <Badge label={riskLevel} tone={toneFromRisk(riskLevel)} />
                    </div>

                    <p className="text-sm text-slate-200 leading-relaxed">{report.final.verdictText}</p>

                    <div className="grid grid-cols-2 gap-2 text-xs text-slate-300 md:grid-cols-4">
                      <div className="rounded-lg border border-white/10 bg-black/25 p-2">
                        <div className="text-[10px] uppercase tracking-[0.14em] text-slate-500">Type</div>
                        <div className="mt-1 font-semibold text-white">{report.intent.type}</div>
                      </div>
                      <div className="rounded-lg border border-white/10 bg-black/25 p-2">
                        <div className="text-[10px] uppercase tracking-[0.14em] text-slate-500">Operation</div>
                        <div className="mt-1 font-semibold text-white">{report.offchain.operation}</div>
                      </div>
                      <div className="rounded-lg border border-white/10 bg-black/25 p-2">
                        <div className="text-[10px] uppercase tracking-[0.14em] text-slate-500">Protocol</div>
                        <div className="mt-1 font-semibold text-white">{report.intent.protocol}</div>
                      </div>
                      <div className="rounded-lg border border-white/10 bg-black/25 p-2">
                        <div className="text-[10px] uppercase tracking-[0.14em] text-slate-500">Network</div>
                        <div className="mt-1 font-semibold text-white">{report.offchain.network}</div>
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-2 rounded-lg border border-yellow-500/30 bg-yellow-500/10 px-3 py-2 text-xs text-yellow-200">
                      <Clock3 size={14} />
                      Mint window freshness: {secondsLeft}s
                      {secondsLeft <= 6 ? (
                        <span className="inline-flex items-center gap-1 text-red-300">
                          <AlertTriangle size={14} /> nearing forced recheck
                        </span>
                      ) : null}
                    </div>
                  </div>
                </div>

                <RiskBreakdown report={report} />

                <div className="flex flex-wrap gap-2 border-t border-white/10 pt-4">
                  <MintReportButton onClick={onMint} status={mintState.status} />
                  <button
                    type="button"
                    onClick={onRecheck}
                    className="btn-outline px-4 py-2 text-[11px]"
                  >
                    Re-run checks
                  </button>
                </div>
                {mintState.status === 'error' ? <p className="text-xs text-red-400">{mintState.error}</p> : null}
              </div>
            )}
          </motion.div>
        </>
      ) : null}
    </AnimatePresence>
  );
}
