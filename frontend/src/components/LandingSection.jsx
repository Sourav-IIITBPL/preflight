import React from 'react';
import { 
  Shield, Zap, Search, Lock, AlertTriangle, Cpu, 
  ArrowRight, Activity, Fingerprint, Database, 
  ShieldCheck, Globe, Code, Layers, FileText
} from 'lucide-react';

export default function LandingSection({ onLaunch }) {
  return (
    <>
      {/* FIXED BACKGROUND SHIELD - Stays centered on screen during scroll */}
      <div className="fixed inset-0 flex items-center justify-center pointer-events-none z-0">
        <Shield 
          size={540} 
          strokeWidth={0.5} 
          className="text-brand-cyan opacity-[0.04] animate-pulse" 
        />
      </div>

      <div className="relative z-10 max-w-6xl mx-auto px-6 py-20">
        
        {/* 1. HERO: The "What" and "Who" */}
        <div className="relative text-center space-y-8 mb-40 pt-10">
          
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-brand-cyan/10 border border-brand-cyan/20 text-brand-cyan text-[11px] font-black uppercase tracking-[0.2em] animate-pulse">
            <Activity size={14} /> Arbitrum Security Gateway v1.0 Active
          </div>
          
          <h1 className="text-7xl font-black tracking-tighter text-white leading-tight">
            Pre<span className="text-brand-cyan">Flight</span>
          </h1>
          
          <p className="text-xl text-slate-400 max-w-3xl mx-auto leading-relaxed font-medium">
            The <span className="text-white font-bold">Zero-Trust DeFi Firewall</span> designed for Arbitrum. 
            We eliminate the blind spots of standard wallet previews by verifying transaction-level integrity in real-time.
          </p>

          <div className="flex flex-col items-center gap-6">
            <button 
              onClick={onLaunch}
              className="btn-primary flex items-center gap-3 px-12 py-5 shadow-[0_0_50px_rgba(0,242,254,0.3)] group relative overflow-hidden"
            >
              Launch Security Layer <ArrowRight size={18} className="group-hover:translate-x-1 transition-transform" />
            </button>
            
            <div className="flex gap-8 text-[10px] text-slate-500 font-bold uppercase tracking-[0.2em]">
              <span>• Swap Integrity</span>
              <span>• Vault Protection</span>
              <span>• LP Safeguards</span>
            </div>
          </div>
        </div>

        {/* 2. THE PHILOSOPHY: Why this exists */}
        <div className="mb-40 grid grid-cols-1 md:grid-cols-2 gap-20 items-center">
          <div className="space-y-6">
            <h2 className="text-3xl font-black text-white uppercase tracking-tight">The Core Philosophy</h2>
            <p className="text-slate-400 leading-relaxed">
              PreFlight is not a price oracle or a simple risk score. It is a <strong>transaction-level security verifier</strong>. 
              We believe a transaction is safe only if the observable on-chain state, execution trace, and accounting invariants match the user’s intent within known risk bounds.
            </p>
            <div className="grid grid-cols-2 gap-4 pt-4">
              <div className="p-4 bg-white/5 rounded-xl border border-white/10">
                <div className="text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider">Zero-Trust</div>
                <p className="text-[10px] text-slate-500">Every router and vault is treated as malicious until verified at the block level.</p>
              </div>
              <div className="p-4 bg-white/5 rounded-xl border border-white/10">
                <div className="text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider">Deterministic</div>
                <p className="text-[10px] text-slate-500">Checks are powered by on-chain Guards that provide immutable proof of safety.</p>
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
                    <div className="text-white">Build User Intent (Frontend)</div>
                  </div>
                  <div className="h-8 w-px bg-white/10 ml-4" />
                  <div className="flex items-center gap-4 text-xs">
                    <div className="w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20">2</div>
                    <div className="text-white font-bold">PreFlight Verification Layer</div>
                  </div>
                  <div className="ml-12 border-l-2 border-brand-cyan/30 pl-4 space-y-2 py-2">
                     <div className="text-[10px] text-slate-500 font-mono italic">├─ On-chain Guards (Deterministic)</div>
                     <div className="text-[10px] text-slate-500 font-mono italic">├─ Off-chain Simulation (Forked)</div>
                     <div className="text-[10px] text-slate-500 font-mono italic">└─ Trace Analyzer (Call Graph)</div>
                  </div>
                  <div className="h-8 w-px bg-white/10 ml-4" />
                  <div className="flex items-center gap-4 text-xs">
                    <div className="w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20">3</div>
                    <div className="text-white">Secure Execution / Abort</div>
                  </div>
               </div>
            </div>
          </div>
        </div>

        {/* 3. THE "HOW": 3-Layer Integrity Model */}
        <div className="mb-40">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-black text-white uppercase tracking-tight">The "How" — 3-Layer Integrity</h2>
            <p className="text-slate-500 mt-2">Our system architecture separates concerns into three distinct verification layers.</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              { 
                icon: <Fingerprint />, 
                title: "State Integrity", 
                who: "On-Chain Guards",
                desc: "Answers: 'Is the pool healthy?' Checks TWAP deviations, reserve snapshots, and pool age. Rejects flash-loan spikes instantly." 
              },
              { 
                icon: <Cpu />, 
                title: "Execution Integrity", 
                who: "Simulation Engine",
                desc: "Answers: 'What happens inside?' Captures internal calls like DELEGATECALL or hidden balance redirections in the call graph." 
              },
              { 
                icon: <Database />, 
                title: "Accounting Integrity", 
                who: "Post-Check Logic",
                desc: "Answers: 'Does the math add up?' Verifies ERC-4626 exchange rates and ensures shares issued match assets deposited." 
              }
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

        {/* 4. THE THREAT MODEL: Detailed Protection Coverage */}
        <div className="mb-40">
          <h2 className="text-3xl font-black text-white uppercase tracking-tight mb-12 text-center">Protocol Threat Models</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {[
              {
                title: "AMM Swap Module",
                desc: "Protects against flash-loan price manipulation and MEV sandwich attacks.",
                checks: ["Spot vs TWAP deviation", "Reserve poisoning detection", "Fee-on-transfer tax verification"],
                id: "SwapGuard.sol"
              },
              {
                title: "ERC-4626 Vault Module",
                desc: "Prevents share-price manipulation and donation/inflation attacks.",
                checks: ["Exchange rate stability", "Asset/Share ratio bounds", "TotalAssets vs BalanceOf check"],
                id: "VaultGuard.sol"
              },
              {
                title: "Liquidity Module",
                desc: "Guards against mintable token rugs and LP redirection traps.",
                checks: ["Token mintability flags", "LP token transfer hooks", "Canonical router check"],
                id: "LiquidityGuard.sol"
              },
              {
                title: "Withdrawal Security",
                desc: "Ensures exit liquidity is returned correctly without reentrancy.",
                checks: ["Call graph inspection", "Exit tax anomaly detection", "Slippage-to-output match"],
                id: "AMMAdapter.sol"
              }
            ].map((item, i) => (
              <div key={i} className="bg-white/[0.02] border border-white/5 p-8 rounded-3xl hover:bg-white/[0.04] transition-colors group">
                <div className="flex justify-between items-start mb-6">
                  <div>
                    <h3 className="text-white font-black uppercase text-sm mb-1">{item.title}</h3>
                    <p className="text-[11px] text-slate-500">{item.desc}</p>
                  </div>
                  <span className="font-mono text-[9px] text-brand-cyan/50 group-hover:text-brand-cyan transition-colors">{item.id}</span>
                </div>
                <div className="space-y-2">
                  {item.checks.map((check, ci) => (
                    <div key={ci} className="flex items-center gap-2 text-[10px] text-slate-400">
                      <ShieldCheck size={12} className="text-brand-cyan/40" /> {check}
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* 5. WHY PREFLIGHT: The Decision Engine */}
        <div className="mb-40 bg-brand-cyan/5 border border-brand-cyan/20 rounded-[3rem] p-16 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-8 opacity-10">
            <Layers size={120} className="text-brand-cyan" />
          </div>
          <div className="max-w-2xl">
            <h2 className="text-3xl font-black text-white uppercase mb-6">Explainable Security</h2>
            <p className="text-slate-400 mb-8 leading-relaxed">
              We don't provide "magic scores." Our Security Layer classifies signals into <strong>INFO</strong>, <strong>WARN</strong>, and <strong>CRITICAL</strong> severities based on formal policy. Invariants are checked at the block level for maximum accuracy.
            </p>
            <div className="flex gap-4">
              <div className="px-4 py-2 bg-red-500/10 border border-red-500/20 text-red-500 text-[10px] font-bold uppercase rounded tracking-widest">Critical: Abort</div>
              <div className="px-4 py-2 bg-yellow-500/10 border border-yellow-500/20 text-yellow-500 text-[10px] font-bold uppercase rounded tracking-widest">Warn: Confirm UI</div>
              <div className="px-4 py-2 bg-brand-cyan/10 border border-brand-cyan/20 text-brand-cyan text-[10px] font-bold uppercase rounded tracking-widest">Info: Pass</div>
            </div>
          </div>
        </div>

        {/* 6. CALL TO ACTION */}
        <div className="relative overflow-hidden rounded-[3rem] p-16 text-center bg-gradient-to-b from-brand-cyan/20 to-transparent border border-brand-cyan/10">
           <div className="absolute top-0 left-0 w-full h-full bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-20 pointer-events-none" />
           <h2 className="text-4xl font-black text-white mb-6 uppercase tracking-tight">Security is not a score.<br/>It's a decision.</h2>
           <p className="text-slate-400 max-w-xl mx-auto mb-10 leading-relaxed text-sm">
              Join the zero-trust revolution on Arbitrum. PreFlight provides judge-verifiable evidence and SBT-based risk reports for every major DeFi interaction.
           </p>
           <button 
             onClick={onLaunch}
             className="btn-primary px-16 py-5 shadow-2xl relative z-10"
           >
             Activate PreFlight Guard
           </button>
         </div>

         {/* Footer Meta */}
        <div className="mt-20 flex justify-center items-center gap-8 opacity-30 grayscale hover:grayscale-0 transition-all duration-700">
          <span className="text-[10px] font-black uppercase tracking-[0.4em]">Audit Verified</span>
          <span className="text-[10px] font-black uppercase tracking-[0.4em]">Arbitrum Native</span>
          <span className="text-[10px] font-black uppercase tracking-[0.4em]">Zero-Knowledge Simulation</span>
        </div>

      </div>
    </>
  );
}





