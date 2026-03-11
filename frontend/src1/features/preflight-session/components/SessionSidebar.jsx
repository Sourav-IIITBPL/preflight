import React, { useMemo } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Link2, Wallet, X, FileSearch2, RefreshCcw, ShieldCheck, Zap } from 'lucide-react';
import CheckTimeline from './CheckTimeline';
import ExecuteTransactionButton from '../../reports/components/ExecuteTransactionButton';
import Button from '../../../shared/ui/Button';
import Badge from '../../../shared/ui/Badge';
import Card from '../../../shared/ui/Card';

function riskTone(level) {
  if (level === 'CRITICAL') return 'critical';
  if (level === 'WARNING') return 'warning';
  return 'success';
}

export default function SessionSidebar({
  isOpen,
  onClose,
  intent,
  onIntentPatch,
  walletGate,
  sessionPhase,
  checkStatus,
  checkError,
  timeline,
  canRunChecks,
  onRunChecks,
  onViewReport,
  hasReport,
  onReset,
  mintState,
  mintedReport,
  executionState,
  onExecute,
}) {
  const walletBadge = useMemo(() => {
    if (!walletGate.isConnected) return { tone: 'critical', label: 'Wallet disconnected' };
    if (!intent.walletConnectedOnTarget) return { tone: 'warning', label: 'Target wallet flag off' };
    return { tone: 'success', label: 'Wallet gate passed' };
  }, [walletGate.isConnected, intent.walletConnectedOnTarget]);

  return (
    <AnimatePresence>
      {isOpen ? (
        <>
          <motion.div
            className="fixed inset-0 z-[110] bg-black/60 backdrop-blur-sm"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          <motion.aside
            className="fixed top-0 right-0 z-[120] w-full h-full glass-card max-w-[430px] flex flex-col shadow-2xl border-l border-brand-cyan/20"
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={{ type: 'spring', damping: 25, stiffness: 200 }}
          >
            <div className="p-5 border-b border-white/5 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-lg bg-brand-cyan/10 flex items-center justify-center border border-brand-cyan/30">
                  <ShieldCheck size={18} className="text-brand-cyan" />
                </div>
                <div>
                  <h2 className="text-base font-black tracking-tight uppercase text-white">PreFlight Session</h2>
                  <p className="text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan/80">Runtime Controls</p>
                </div>
              </div>
              <button onClick={onClose} className="p-2 hover:bg-white/5 rounded-full text-gray-500 hover:text-white transition-all">
                <X size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-5 space-y-4">
              <Card>
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2 text-sm font-bold text-white">
                    <Wallet size={16} /> Wallet Gate
                  </div>
                  <Badge label={walletBadge.label} tone={walletBadge.tone} />
                </div>

                <div className="mt-3 flex flex-wrap gap-2">
                  <Button
                    variant={walletGate.isConnected ? 'ghost' : 'primary'}
                    className="min-w-[150px]"
                    onClick={walletGate.isConnected ? walletGate.disconnectWallet : walletGate.connectWallet}
                  >
                    {walletGate.isConnected ? 'Disconnect Wallet' : 'Connect Wallet'}
                  </Button>

                  <label className="inline-flex items-center gap-2 rounded-lg border border-white/15 bg-black/35 px-3 py-2 text-[11px] text-slate-300">
                    <input
                      type="checkbox"
                      checked={Boolean(intent.walletConnectedOnTarget)}
                      onChange={(event) => onIntentPatch({ walletConnectedOnTarget: event.target.checked })}
                    />
                    Wallet connected on target
                  </label>
                </div>

                {walletGate.error ? <p className="mt-2 text-[11px] text-red-400">{walletGate.error}</p> : null}
              </Card>

                <Card>
                  <div className="mb-2 flex items-center justify-between">
                    <div className="flex items-center gap-2 text-sm font-bold text-white">
                      <Link2 size={16} /> Intent Source
                  </div>
                  <Badge label={intent.type} tone="info" />
                </div>

                <div className="grid grid-cols-2 gap-2 text-xs">
                  <label className="space-y-1 col-span-2">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Target URL</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70"
                      value={intent.targetUrl ?? ''}
                      onChange={(event) => onIntentPatch({ targetUrl: event.target.value })}
                      placeholder="https://app.camelot.exchange"
                    />
                  </label>

                  <label className="space-y-1 col-span-2">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Sender (from)</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono"
                      value={intent.from ?? ''}
                      onChange={(event) => onIntentPatch({ from: event.target.value })}
                      placeholder="0x..."
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Protocol</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70"
                      value={intent.protocol}
                      onChange={(event) => onIntentPatch({ protocol: event.target.value })}
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Operation</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70"
                      value={intent.opType}
                      onChange={(event) => onIntentPatch({ opType: event.target.value })}
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Pair / Vault</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70"
                      value={intent.payload?.pair ?? ''}
                      onChange={(event) => onIntentPatch({ payload: { pair: event.target.value } })}
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Amount</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70"
                      value={intent.payload?.amount ?? ''}
                      onChange={(event) => onIntentPatch({ payload: { amount: event.target.value } })}
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Router Address</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono"
                      value={intent.payload?.routerAddress ?? ''}
                      onChange={(event) => onIntentPatch({ payload: { routerAddress: event.target.value } })}
                      placeholder="0x..."
                    />
                  </label>

                  <label className="space-y-1">
                    <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Vault Address</span>
                    <input
                      className="w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono"
                      value={intent.payload?.vaultAddress ?? ''}
                      onChange={(event) => onIntentPatch({ payload: { vaultAddress: event.target.value } })}
                      placeholder="0x..."
                    />
                  </label>
                </div>

                <label className="mt-2 block space-y-1 text-xs">
                  <span className="text-[10px] uppercase tracking-[0.15em] text-slate-500">Transaction Calldata (hex)</span>
                  <textarea
                    className="min-h-[76px] w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono"
                    value={intent.payload?.data ?? ''}
                    onChange={(event) => onIntentPatch({ payload: { data: event.target.value } })}
                    placeholder="0x..."
                  />
                </label>

                <p className="mt-2 text-[10px] text-slate-500 leading-relaxed">
                  For real CRE off-chain checks, set `from`, router/vault, and calldata fields so payload matches the simulation trigger format.
                </p>
              </Card>

              <Card>
                <div className="mb-3 flex items-center justify-between">
                  <div className="flex items-center gap-2 text-sm font-bold text-white">
                    <FileSearch2 size={16} /> Check Timeline
                  </div>
                  <Badge label={sessionPhase.replaceAll('_', ' ')} tone="neutral" />
                </div>

                {checkError ? (
                  <p className="mb-2 rounded-lg border border-red-500/20 bg-red-500/10 px-2 py-1 text-xs text-red-300">{checkError}</p>
                ) : null}

                <CheckTimeline timeline={timeline} />

                <div className="pt-3 mt-3 border-t border-white/5 space-y-2">
                  <button
                    onClick={onRunChecks}
                    disabled={!canRunChecks || checkStatus === 'running'}
                    className="w-full py-3 bg-brand-cyan hover:brightness-110 text-black font-black rounded-xl transition-all neon-glow flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed"
                  >
                    <Zap size={16} fill="black" /> {checkStatus === 'running' ? 'RUNNING CHECK PREFLIGHT...' : 'CHECK PREFLIGHT'}
                  </button>

                  <div className="flex gap-2">
                    <Button variant="ghost" className="flex-1" onClick={onViewReport} disabled={!hasReport}>
                      View Report
                    </Button>
                    <Button variant="ghost" className="flex-1" onClick={onReset}>
                      <RefreshCcw size={14} className="mr-1" /> Reset
                    </Button>
                  </div>
                </div>
              </Card>

              <Card>
                <div className="mb-3 flex items-center justify-between">
                  <p className="text-sm font-bold text-white">Post-check Actions</p>
                  {mintedReport ? <Badge label={mintedReport.riskLevel} tone={riskTone(mintedReport.riskLevel)} /> : <Badge label="Not minted" tone="warning" />}
                </div>

                {mintState.status === 'pending' ? <p className="text-xs text-brand-cyan">Minting report NFT...</p> : null}
                {mintState.status === 'error' ? <p className="text-xs text-red-400">{mintState.error}</p> : null}

                {mintedReport ? (
                  <div className="space-y-2 text-xs rounded-lg bg-white/[0.02] border border-white/10 p-3">
                    <p className="text-slate-300">Token ID: #{mintedReport.tokenId}</p>
                    <p className="font-mono text-slate-500 text-[11px] break-all">{mintedReport.txHash}</p>
                  </div>
                ) : (
                  <p className="text-xs text-slate-400">Mint report in modal to unlock guarded execution.</p>
                )}

                <div className="mt-3">
                  <ExecuteTransactionButton onClick={onExecute} disabled={!mintedReport || executionState.status === 'pending'} status={executionState.status} />
                </div>

                {executionState.status === 'success' ? (
                  <p className="mt-2 rounded-lg border border-green-500/25 bg-green-500/10 px-2 py-1 text-xs text-green-300">Transaction executed successfully.</p>
                ) : null}

                {executionState.status === 'error' ? (
                  <p className="mt-2 rounded-lg border border-red-500/25 bg-red-500/10 px-2 py-1 text-xs text-red-300">{executionState.error}</p>
                ) : null}
              </Card>
            </div>

            <div className="p-4 bg-black/40 border-t border-white/5 flex items-center justify-center gap-2">
              <div className="w-1.5 h-1.5 rounded-full bg-green-500 shadow-[0_0_5px_#22c55e]" />
              <span className="text-[9px] font-bold text-gray-500 uppercase tracking-[0.3em]">Arbitrum One Mainnet Active</span>
            </div>
          </motion.aside>
        </>
      ) : null}
    </AnimatePresence>
  );
}
