import React from 'react';
import { motion } from 'framer-motion';
import {
  ArrowRight,
  ShieldCheck,
  Layers,
  Sparkles,
  Zap,
  Lock,
  Eye,
  AlertTriangle,
  Cpu,
  Fingerprint,
  ChevronDown
} from 'lucide-react';
import Button from './ui/Button';
import Card from './ui/Card';
import Logo from './ui/Logo';

const fadeInUp = {
  hidden: { opacity: 0, y: 20 },
  visible: { 
    opacity: 1, 
    y: 0,
    transition: { duration: 0.8, ease: [0.16, 1, 0.3, 1] }
  }
};

const staggerContainer = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.2
    }
  }
};

export default function LandingSection({ onOpenInstall, onOpenPortfolio }) {
  return (
    <>
      <motion.div 
        className="relative z-10 mx-auto max-w-6xl px-6"
        variants={staggerContainer}
        initial="hidden"
        animate="visible"
      >
        {/* HERO SECTION */}
        <section className="min-h-[90vh] flex flex-col items-center justify-center text-center pt-20 pb-32">
          <motion.div variants={fadeInUp} className="mb-6">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-brand-cyan/20 bg-brand-cyan/5 backdrop-blur-sm">
              <Sparkles size={14} className="text-brand-cyan" />
              <span className="text-[10px] font-black uppercase tracking-[0.4em] text-brand-cyan">Verified Security</span>
            </div>
          </motion.div>

          <motion.div variants={fadeInUp} className="relative mb-8">
             <span className="font-cursive text-3xl md:text-4xl text-brand-cyan/80 block mb-2 -rotate-2">Welcome To</span>
             <h1 className="text-6xl md:text-8xl lg:text-9xl font-black text-white tracking-tighter leading-[0.8] mb-4">
              PreFlight
            </h1>
            <p className="font-cursive text-2xl md:text-3xl text-slate-400">
              The First Pre-Transaction Security Layer for DeFi
            </p>
          </motion.div>

          <motion.div variants={fadeInUp} className="max-w-4xl space-y-6 mb-12">
            <h2 className="text-2xl md:text-4xl font-bold text-white tracking-tight">
              Verify Every DeFi Transaction <span className="gradient-text">Before It Executes</span>
            </h2>
            
            <p className="mx-auto max-w-2xl text-lg text-slate-400 leading-relaxed font-medium">
              PreFlight intercepts your transactions, simulates them in a forked environment, 
              validates them on-chain, and mints a verifiable risk report — <span className="text-brand-cyan italic">before execution</span>.
            </p>
          </motion.div>

          {/* SCANNING LOGO AT CENTER */}
          <motion.div 
            variants={fadeInUp}
            className="relative mb-16 group"
          >
            <div className="absolute inset-0 bg-brand-cyan/20 blur-[100px] rounded-full scale-125 opacity-50 group-hover:opacity-70 transition-opacity duration-700" />
            <div className="relative glass-card p-8 rounded-full border-brand-cyan/30">
                <Logo className="h-48 w-48 md:h-64 md:w-64 text-brand-cyan" animated={true} />
                <div className="absolute inset-0 rounded-full border-2 border-brand-cyan/20 animate-ping" />
            </div>
          </motion.div>

          <motion.div 
            variants={fadeInUp}
            className="flex flex-col items-center justify-center gap-6 sm:flex-row w-full max-w-lg"
          >
            <Button onClick={onOpenInstall} className="w-full sm:w-auto px-12 py-5 text-sm shadow-[0_0_60px_rgba(0,242,254,0.3)]">
              Install Extension <ArrowRight size={18} />
            </Button>
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full sm:w-auto px-12 py-5 text-sm">
              View How It Works
            </Button>
          </motion.div>

          <motion.div variants={fadeInUp} className="mt-20 animate-bounce text-slate-500">
            <ChevronDown size={24} />
          </motion.div>
        </section>

        {/* PROBLEM SECTION */}
        <section className="py-32">
          <motion.div variants={fadeInUp} className="text-center mb-20">
             <div className="inline-flex items-center gap-2 mb-4 text-red-400 font-bold uppercase tracking-widest text-xs">
              <AlertTriangle size={16} /> The Problem
            </div>
            <h2 className="text-4xl md:text-6xl font-black text-white mb-6 uppercase">DeFi Execution Is Blind</h2>
          </motion.div>

          <div className="grid md:grid-cols-2 gap-8 items-center">
             <div className="space-y-6">
                <p className="text-xl text-slate-300 font-medium leading-relaxed">
                  Wallets only show calldata, not consequences. You are signing transactions without knowing their actual outcome.
                </p>
                <div className="space-y-4">
                  {[
                    "Cannot simulate execution",
                    "Unable to detect vault exploits",
                    "Vulnerable to slippage & token behavior",
                    "Flash loan, MEV, and low liquidity attacks"
                  ].map((text, i) => (
                    <div key={i} className="flex items-center gap-3 text-slate-400">
                      <div className="h-1.5 w-1.5 rounded-full bg-red-500/50" />
                      <span>{text}</span>
                    </div>
                  ))}
                </div>
                <div className="pt-6 border-t border-white/5">
                   <p className="text-2xl font-black text-red-400 uppercase italic">
                    You sign without knowing.
                   </p>
                </div>
             </div>
             <div className="relative">
                <div className="absolute inset-0 bg-red-500/10 blur-[80px] rounded-full" />
                <Card className="glass-card p-8 border-red-500/20 relative overflow-hidden">
                   <div className="text-red-500 mb-6"><AlertTriangle size={48} /></div>
                   <h3 className="text-2xl font-bold text-white mb-4">Vulnerability Matrix</h3>
                   <div className="space-y-4 opacity-60">
                      <div className="h-4 bg-red-500/20 rounded w-full" />
                      <div className="h-4 bg-red-500/20 rounded w-3/4" />
                      <div className="h-4 bg-red-500/20 rounded w-5/6" />
                   </div>
                </Card>
             </div>
          </div>
        </section>

        {/* SOLUTION SECTION */}
        <section className="py-32">
           <motion.div variants={fadeInUp} className="text-center mb-20">
             <div className="inline-flex items-center gap-2 mb-4 text-brand-cyan font-bold uppercase tracking-widest text-xs">
              <ShieldCheck size={16} /> The Solution
            </div>
            <h2 className="text-4xl md:text-6xl font-black text-white mb-6 uppercase">Deterministic Verification Layer</h2>
          </motion.div>

          <div className="relative">
            {/* Flow Diagram */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-8 relative z-10">
               {[
                 { title: "Intercept", icon: <Zap />, desc: "Extension catches intent before signature." },
                 { title: "Simulate", icon: <Cpu />, desc: "Forked EVM environment execution." },
                 { title: "Validate", icon: <Lock />, desc: "On-chain guards enforce invariants." }
               ].map((step, i) => (
                 <Card key={i} className="glass-card p-8 text-center group">
                    <div className="mx-auto w-16 h-16 rounded-2xl bg-brand-cyan/10 text-brand-cyan flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
                      {step.icon}
                    </div>
                    <h3 className="text-xl font-bold text-white mb-2">{step.title}</h3>
                    <p className="text-slate-400 text-sm">{step.desc}</p>
                 </Card>
               ))}
            </div>
            {/* Connection Lines (Desktop) */}
            <div className="hidden md:block absolute top-1/2 left-0 w-full h-px bg-gradient-to-r from-transparent via-brand-cyan/20 to-transparent -translate-y-1/2 z-0" />
          </div>

          <div className="mt-20 grid md:grid-cols-2 lg:grid-cols-4 gap-6">
             {[
               "Token safety check",
               "Real-time constraints",
               "Vault invariants (ERC-4626)",
               "State diff computation"
             ].map((feature, i) => (
               <div key={i} className="flex items-center gap-3 p-4 glass-card rounded-2xl">
                 <ShieldCheck size={16} className="text-brand-cyan" />
                 <span className="text-xs font-bold uppercase tracking-wider text-slate-300">{feature}</span>
               </div>
             ))}
          </div>
        </section>

        {/* OFF-CHAIN SIMULATION */}
        <section className="py-32 border-t border-white/5">
           <div className="grid md:grid-cols-2 gap-20 items-center">
              <div className="order-2 md:order-1">
                 <div className="relative glass-card p-1 aspect-square rounded-[3rem] overflow-hidden">
                    <div className="absolute inset-0 bg-brand-cyan/5 animate-pulse" />
                    <div className="relative h-full w-full bg-black/40 rounded-[2.8rem] p-8 flex flex-col justify-between">
                       <div className="flex justify-between items-start">
                          <Cpu className="text-brand-cyan" size={32} />
                          <div className="text-[10px] font-mono text-brand-cyan/60 uppercase">Fork: Mainnet-latest</div>
                       </div>
                       <div className="space-y-4 font-mono text-xs text-brand-cyan/40">
                          <div className="flex gap-4"><span>&gt;</span> <span className="text-brand-cyan/80">Simulating tx...</span></div>
                          <div className="flex gap-4"><span>&gt;</span> <span>State diff computed</span></div>
                          <div className="flex gap-4"><span>&gt;</span> <span>Balance changes: +1.2 ETH</span></div>
                          <div className="flex gap-4"><span>&gt;</span> <span className="text-emerald-400">Verdict: SAFE</span></div>
                       </div>
                    </div>
                 </div>
              </div>
              <div className="order-1 md:order-2 space-y-8">
                <h2 className="text-4xl md:text-5xl font-black text-white uppercase leading-tight">
                  Fork-Based <br /> Execution Simulation
                </h2>
                <p className="text-lg text-slate-400 leading-relaxed font-medium">
                  A forked EVM environment is created from the latest chain state. The exact transaction is executed before actual submission.
                </p>
                <div className="grid grid-cols-2 gap-6">
                   {[
                     { label: "State Diffs", sub: "Actual vs Predicted" },
                     { label: "Balance Changes", sub: "Exact token shifts" },
                     { label: "Vault Behavior", sub: "Share inflation check" },
                     { label: "Slippage", sub: "Deterministic outcomes" }
                   ].map((item, i) => (
                     <div key={i}>
                        <div className="text-brand-cyan font-bold uppercase tracking-widest text-[10px] mb-1">{item.label}</div>
                        <div className="text-white text-sm font-medium">{item.sub}</div>
                     </div>
                   ))}
                </div>
                <p className="font-cursive text-2xl text-brand-cyan pt-6">
                  Not estimation — deterministic execution.
                </p>
              </div>
           </div>
        </section>

        {/* ON-CHAIN GUARDS */}
        <section className="py-32">
           <motion.div variants={fadeInUp} className="text-center mb-20">
            <h2 className="text-4xl md:text-5xl font-black text-white mb-6 uppercase">On-Chain Guards Enforce Safety</h2>
          </motion.div>

          <div className="grid md:grid-cols-3 gap-8">
             {[
               {
                 title: "SwapGuard",
                 icon: <Zap size={24} />,
                 items: ["Slippage bounds", "Execution deviation", "Flash loan defense"]
               },
               {
                 title: "TokenGuard",
                 icon: <Fingerprint size={24} />,
                 items: ["Malicious token detection", "Rug-pull heuristics", "Honeypot checks"]
               },
               {
                 title: "VaultGuard",
                 icon: <Lock size={24} />,
                 items: ["ERC-4626 invariants", "Donation attack protection", "Share inflation risks"]
               }
             ].map((guard, i) => (
               <Card key={i} className="glass-card p-10 border-brand-cyan/10 hover:border-brand-cyan/30">
                  <div className="w-12 h-12 rounded-xl bg-brand-cyan/10 text-brand-cyan flex items-center justify-center mb-6">
                    {guard.icon}
                  </div>
                  <h3 className="text-2xl font-black text-white mb-6 uppercase tracking-tight">{guard.title}</h3>
                  <ul className="space-y-4">
                     {guard.items.map((item, j) => (
                       <li key={j} className="flex items-center gap-3 text-sm text-slate-400 font-medium">
                         <div className="h-1 w-3 bg-brand-cyan/30 rounded-full" />
                         {item}
                       </li>
                     ))}
                  </ul>
               </Card>
             ))}
          </div>
        </section>

        {/* RISK REPORT NFT */}
        <section className="py-32 relative overflow-hidden">
           <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full h-full bg-brand-cyan/5 blur-[120px] rounded-full pointer-events-none" />
           <div className="text-center space-y-8 relative z-10">
              <h2 className="text-4xl md:text-6xl font-black text-white uppercase">Verifiable Proof for Every Move</h2>
              <p className="mx-auto max-w-2xl text-xl text-slate-400 font-medium">
                Each verified transaction mints an NFT containing risk flags and validation outputs.
              </p>
              <div className="mx-auto max-w-sm glass-card p-4 rounded-[2rem] border-brand-cyan/20">
                 <div className="aspect-square bg-slate-900 rounded-[1.5rem] flex flex-col items-center justify-center p-8 text-center border border-white/5">
                    <Layers className="text-brand-cyan mb-4" size={48} />
                    <div className="text-xs font-mono text-brand-cyan/60 mb-2">PreFlight Risk Report #482</div>
                    <div className="px-3 py-1 bg-emerald-500/10 text-emerald-400 rounded-full text-[10px] font-black uppercase tracking-widest border border-emerald-500/20">
                      Validated
                    </div>
                 </div>
              </div>
              <p className="font-cursive text-3xl text-brand-cyan">
                A permanent record of transaction safety.
              </p>
           </div>
        </section>

        {/* TRUST SECTION */}
        <section className="py-32 grid md:grid-cols-4 gap-8">
           {[
             { label: "No Blind Execution", desc: "Always know the outcome before signing." },
             { label: "Transparent Logic", desc: "Open-source guards anyone can verify." },
             { label: "Immutable Evidence", desc: "Reports stored forever on the blockchain." },
             { label: "Real-time Defenses", desc: "Active protection against evolving threats." }
           ].map((item, i) => (
             <div key={i} className="space-y-4">
               <div className="h-1 w-12 bg-brand-cyan" />
               <h4 className="text-lg font-black text-white uppercase tracking-tight">{item.label}</h4>
               <p className="text-sm text-slate-500 leading-relaxed">{item.desc}</p>
             </div>
           ))}
        </section>

        {/* FINAL CTA */}
        <section className="py-32">
           <div className="glass-card rounded-[4rem] p-12 md:p-24 text-center border-brand-cyan/20 bg-gradient-to-br from-brand-cyan/10 to-transparent">
              <h2 className="text-5xl md:text-7xl font-black text-white uppercase mb-12 leading-tight">Secure Your <br /> DeFi Workflow</h2>
              <div className="flex flex-col sm:flex-row justify-center gap-6">
                <Button onClick={onOpenInstall} className="px-16 py-6 text-base font-black uppercase tracking-[0.2em]">
                   Install Extension
                </Button>
                <Button variant="ghost" onClick={onOpenPortfolio} className="px-16 py-6 text-base font-black uppercase tracking-[0.2em]">
                   Go to Portfolio
                </Button>
              </div>
           </div>
        </section>
      </motion.div>
    </>
  );
}
