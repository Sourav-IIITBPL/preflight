import React from 'react';
import {
  Shield,
  ArrowRight,
  Activity,
  Fingerprint,
  Database,
  ShieldCheck,
  Layers,
  AlertTriangle,
  Clock3,
  Globe,
} from 'lucide-react';

export default function LandingSection({ onLaunch, isLaunched = false }) {
  return (
    <>
      <div className="fixed inset-0 flex items-center justify-center pointer-events-none z-0">
        <Shield
          size={540}
          strokeWidth={0.5}
          className="text-brand-cyan opacity-[0.04] animate-pulse"
        />
      </div>

      <div className="relative z-10 max-w-6xl mx-auto px-6 py-20">
        <div className="relative text-center space-y-8 mb-40 pt-10">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-brand-cyan/10 border border-brand-cyan/20 text-brand-cyan text-[11px] font-black uppercase tracking-[0.2em] animate-pulse">
            <Activity size={14} /> Arbitrum Security Gateway v1.0 Active
          </div>

          <h1 className="text-7xl font-black tracking-tighter text-white leading-tight">
            Pre<span className="text-brand-cyan">Flight</span>
          </h1>

          <p className="text-xl text-slate-400 max-w-4xl mx-auto leading-relaxed font-medium">
            PreFlight is a <span className="text-white font-bold">transaction security layer</span> for Arbitrum DeFi.
            It validates user intent before execution by combining off-chain CRE simulation, deterministic guard checks,
            and policy-based verdicts in one explainable workflow.
          </p>
          <p className="text-sm text-slate-500 max-w-3xl mx-auto">
            Launch flow: choose DEX (Camelot or SaucerSwap) -&gt; open secure DEX runtime page -&gt; intercept intent -&gt; run checks -&gt; mint report -&gt; execute.
          </p>

          <div className="flex flex-col items-center gap-6">
            <button
              onClick={onLaunch}
              className="btn-primary flex items-center gap-3 px-12 py-5 shadow-[0_0_50px_rgba(0,242,254,0.3)] group relative overflow-hidden"
            >
              {isLaunched ? 'PreFlight Launcher Active' : 'Launch Security Layer'}
              <ArrowRight size={18} className="group-hover:translate-x-1 transition-transform" />
            </button>

            <div className="flex flex-wrap justify-center gap-6 text-[10px] text-slate-500 font-bold uppercase tracking-[0.2em]">
              <span>• Swap Integrity</span>
              <span>• Vault Protection</span>
              <span>• LP Safeguards</span>
              <span>• Report NFT Proof</span>
            </div>
          </div>
        </div>

        <div className="mb-40 grid grid-cols-1 md:grid-cols-2 gap-20 items-center">
          <div className="space-y-6">
            <h2 className="text-3xl font-black text-white uppercase tracking-tight">Why This Exists</h2>
            <p className="text-slate-400 leading-relaxed">
              Wallet previews mostly show top-level calls and outputs. Many failures happen in internal routes,
              adapter hops, vault accounting, or temporary manipulation windows. PreFlight was designed to expose those
              blind spots before you submit execution.
            </p>
            <div className="grid grid-cols-2 gap-4 pt-4">
              <div className="p-4 bg-white/5 rounded-xl border border-white/10">
                <div className="text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider">Zero-Trust</div>
                <p className="text-[10px] text-slate-500">Routers, pools, and vault paths are treated as untrusted by default.</p>
              </div>
              <div className="p-4 bg-white/5 rounded-xl border border-white/10">
                <div className="text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider">Explainable</div>
                <p className="text-[10px] text-slate-500">Each decision includes trace, economics, and policy evidence for users.</p>
              </div>
            </div>
          </div>

          <div className="relative">
            <div className="absolute -inset-4 bg-brand-cyan/20 blur-3xl opacity-20 rounded-full" />
            <div className="relative glass-card p-8 rounded-3xl border border-white/10">
              <div className="text-[10px] font-mono text-brand-cyan mb-4 uppercase tracking-[0.2em]">System_Logic::Abstraction</div>
              <div className="space-y-4">
                <div className="flex items-center gap-4 text-xs">
                  <div className="w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20">1</div>
                  <div className="text-white">Capture User Intent</div>
                </div>
                <div className="h-8 w-px bg-white/10 ml-4" />
                <div className="flex items-center gap-4 text-xs">
                  <div className="w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20">2</div>
                  <div className="text-white font-bold">Run PreFlight Verification</div>
                </div>
                <div className="ml-12 border-l-2 border-brand-cyan/30 pl-4 space-y-2 py-2">
                  <div className="text-[10px] text-slate-500 font-mono italic">├─ Off-chain simulation (CRE)</div>
                  <div className="text-[10px] text-slate-500 font-mono italic">├─ On-chain guards (router-level)</div>
                  <div className="text-[10px] text-slate-500 font-mono italic">└─ Risk policy aggregation</div>
                </div>
                <div className="h-8 w-px bg-white/10 ml-4" />
                <div className="flex items-center gap-4 text-xs">
                  <div className="w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20">3</div>
                  <div className="text-white">Mint Report NFT and Execute</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="mb-40">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-black text-white uppercase tracking-tight">How PreFlight Protects You</h2>
            <p className="text-slate-500 mt-2">Three-layer integrity model with deterministic and simulated checks.</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              {
                icon: <Fingerprint />,
                title: 'State Integrity',
                who: 'On-Chain Guards',
                desc: 'Checks pool/vault state invariants and rejects paths outside safe policy bounds.',
              },
              {
                icon: <Layers />,
                title: 'Execution Integrity',
                who: 'Simulation Engine',
                desc: 'Simulates path-level behavior to surface hidden call effects and unsafe route behavior.',
              },
              {
                icon: <Database />,
                title: 'Accounting Integrity',
                who: 'Post-Check Policy',
                desc: 'Validates output consistency, slippage boundaries, and accounting assumptions.',
              },
            ].map((card, i) => (
              <div key={i} className="group glass-card p-10 rounded-[2.5rem] border border-white/5 hover:border-brand-cyan/40 transition-all duration-500">
                <div className="text-brand-cyan mb-6 group-hover:scale-110 transition-transform">{card.icon}</div>
                <div className="text-[10px] font-black text-brand-cyan uppercase tracking-widest mb-2">{card.who}</div>
                <div className="text-white font-black mb-4 uppercase text-sm tracking-widest">{card.title}</div>
                <p className="text-slate-400 text-xs leading-relaxed">{card.desc}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="mb-40 bg-brand-cyan/5 border border-brand-cyan/20 rounded-[3rem] p-10 md:p-16 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-8 opacity-10">
            <Globe size={120} className="text-brand-cyan" />
          </div>
          <div className="max-w-3xl space-y-5">
            <h2 className="text-3xl font-black text-white uppercase">Trust Through Transparency</h2>
            <p className="text-slate-400 leading-relaxed">
              PreFlight is built to reduce risk, not to make impossible guarantees. No security system can guarantee 100% safety
              under all market and smart-contract conditions. The product is strongest when users can inspect clear evidence,
              understand risk levels, and decide with context.
            </p>
            <div className="grid gap-3 md:grid-cols-3 text-[11px]">
              <div className="rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300">
                <span className="text-brand-cyan font-bold uppercase tracking-widest text-[10px]">Current coverage</span>
                <p className="mt-1">Arbitrum-focused swap, liquidity, and vault pre-check workflows.</p>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300">
                <span className="text-brand-cyan font-bold uppercase tracking-widest text-[10px]">Known limits</span>
                <p className="mt-1">Cross-tab intent capture is partial without extension-based content adapters.</p>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300">
                <span className="text-brand-cyan font-bold uppercase tracking-widest text-[10px]">Roadmap</span>
                <p className="mt-1">Arbitrum first, then protocol adapters for Uni, Sushi, and multi-chain expansion.</p>
              </div>
            </div>
          </div>
        </div>

        <div className="mb-40">
          <h2 className="text-3xl font-black text-white uppercase tracking-tight mb-10 text-center">User Safety Flow</h2>
          <div className="grid gap-6 md:grid-cols-4">
            {[
              { icon: <ShieldCheck size={14} />, label: 'Wallet gate', text: 'Check starts only after wallet is connected.' },
              { icon: <Clock3 size={14} />, label: 'Freshness guard', text: 'Report is revalidated if preview becomes stale (>20s).' },
              { icon: <Database size={14} />, label: 'Mint proof', text: 'Risk report can be minted to preserve evidence.' },
              { icon: <AlertTriangle size={14} />, label: 'Execute guard', text: 'Execution remains behind risk-aware route controls.' },
            ].map((item, i) => (
              <div key={i} className="bg-white/[0.02] border border-white/5 p-6 rounded-3xl hover:bg-white/[0.04] transition-colors">
                <div className="inline-flex items-center justify-center w-8 h-8 rounded-lg bg-brand-cyan/10 border border-brand-cyan/25 text-brand-cyan mb-3">
                  {item.icon}
                </div>
                <h3 className="text-white font-black uppercase text-[11px] tracking-widest mb-2">{item.label}</h3>
                <p className="text-[11px] text-slate-500 leading-relaxed">{item.text}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="relative overflow-hidden rounded-[3rem] p-16 text-center bg-gradient-to-b from-brand-cyan/20 to-transparent border border-brand-cyan/10">
          <div className="absolute top-0 left-0 w-full h-full bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-20 pointer-events-none" />
          <h2 className="text-4xl font-black text-white mb-6 uppercase tracking-tight">Security Is A Process, Not A Checkbox</h2>
          <p className="text-slate-400 max-w-2xl mx-auto mb-10 leading-relaxed text-sm">
            Launch PreFlight before every sensitive DeFi action. Review risk evidence, mint audit-ready reports, and execute with
            stronger confidence than raw wallet previews alone.
          </p>
          <button
            onClick={onLaunch}
            className="btn-primary px-16 py-5 shadow-2xl relative z-10"
          >
            {isLaunched ? 'Launcher Already Active' : 'Activate PreFlight Guard'}
          </button>
        </div>
      </div>
    </>
  );
}
