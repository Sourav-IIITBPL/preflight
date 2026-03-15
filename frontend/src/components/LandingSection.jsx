import React from 'react';
import { motion } from 'framer-motion';
import {
  ArrowRight,
  ShieldCheck,
  Layers,
  Sparkles,
  Zap,
  Lock,
  Eye
} from 'lucide-react';
import { SUPPORTED_DEXES } from '../constants';
import Button from './ui/Button';
import Card from './ui/Card';
import Badge from './ui/Badge';
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
      {/* Dynamic Background Elements - Subtle */}
      <div className="fixed inset-0 z-0 pointer-events-none flex items-center justify-center">
        <motion.div 
          initial={{ opacity: 0, scale: 0.8 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 2 }}
          className="w-[100vw] h-[100vw] bg-brand-cyan/[0.03] rounded-full blur-[160px]" 
        />
      </div>

      <motion.div 
        className="relative z-10 mx-auto max-w-6xl px-6"
        variants={staggerContainer}
        initial="hidden"
        animate="visible"
      >
        {/* HERO SECTION - Upper Half */}
        <section className="min-h-[90vh] flex flex-col items-center justify-center text-center pt-20 pb-32">
          
          <motion.div variants={fadeInUp} className="mb-6">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full border border-brand-cyan/20 bg-brand-cyan/5 backdrop-blur-sm">
              <Sparkles size={14} className="text-brand-cyan" />
              <span className="text-[10px] font-black uppercase tracking-[0.4em] text-brand-cyan">Introducing PreFlight</span>
            </div>
          </motion.div>

          {/* MASSIVE CENTER LOGO */}
          <motion.div 
            variants={fadeInUp}
            className="relative mb-12"
          >
            <div className="absolute inset-0 bg-brand-cyan/20 blur-[120px] rounded-full scale-125 opacity-50" />
            <Logo className="h-64 w-64 md:h-[30rem] md:w-[30rem] text-brand-cyan drop-shadow-[0_0_50px_rgba(0,242,254,0.2)]" animated={true} />
          </motion.div>

          <motion.div variants={fadeInUp} className="max-w-4xl space-y-6">
            <h1 className="text-5xl md:text-7xl lg:text-8xl font-black text-white tracking-tighter leading-[0.9]">
              The First <br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-brand-cyan via-white to-brand-cyan bg-[length:200%_auto] animate-gradient-x">
                Pre-Transaction
              </span> <br />
              Security Layer
            </h1>
            
            <p className="mx-auto max-w-2xl text-lg md:text-xl font-medium text-slate-400 leading-relaxed">
              Interpose trust between your intent and the blockchain. 
              Verify, simulate, and defend your capital before the signature.
            </p>
          </motion.div>

          <motion.div 
            variants={fadeInUp}
            className="mt-12 flex flex-col items-center justify-center gap-6 sm:flex-row w-full max-w-lg"
          >
            <Button onClick={onOpenInstall} className="w-full sm:w-auto px-12 py-5 text-sm shadow-[0_0_60px_rgba(0,242,254,0.3)] hover:shadow-[0_0_80px_rgba(0,242,254,0.5)] transition-all">
              Secure Chrome <ArrowRight size={18} />
            </Button>
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full sm:w-auto px-12 py-5 text-sm border-white/10 hover:bg-white/5">
              Protocol Dashboard
            </Button>
          </motion.div>

          {/* Quick Stats / Highlights */}
          <motion.div 
            variants={fadeInUp}
            className="mt-24 grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-16 opacity-50"
          >
            {[
              { icon: <Zap size={16} />, label: "Real-time" },
              { icon: <Lock size={16} />, label: "Zero-Trust" },
              { icon: <Eye size={16} />, label: "Explainable" },
              { icon: <ShieldCheck size={16} />, label: "On-Chain" },
            ].map((stat, i) => (
              <div key={i} className="flex flex-col items-center gap-2">
                <div className="text-brand-cyan">{stat.icon}</div>
                <span className="text-[10px] font-bold uppercase tracking-widest text-slate-300">{stat.label}</span>
              </div>
            ))}
          </motion.div>
        </section>

        {/* VALUE PROPOSITION SECTION */}
        <section className="mb-48 grid gap-20 md:grid-cols-2 md:items-center">
          <div className="space-y-10 text-left">
            <div className="space-y-4">
              <h2 className="text-4xl md:text-5xl font-black uppercase tracking-tight text-white leading-tight">
                Security by <br /> Interception
              </h2>
              <p className="text-lg leading-relaxed text-slate-400 font-medium">
                Traditional wallets only show you a preview. PreFlight operates at the protocol level, 
                decoding raw calldata and simulating outcomes in a high-fidelity sandbox.
              </p>
            </div>

            <div className="grid gap-6">
              {[
                { label: "Sandbox Simulation", text: "Run every transaction in a risk-free environment first.", icon: <ShieldCheck size={20} /> },
                { label: "Immutable Evidence", text: "Security verdicts are recorded as NFTs on Arbitrum One.", icon: <Layers size={20} /> }
              ].map((box, i) => (
                <div 
                  key={i}
                  className="rounded-3xl border border-white/5 bg-white/[0.02] p-8 hover:border-brand-cyan/30 transition-all group"
                >
                  <div className="flex items-center gap-4 mb-4">
                    <div className="p-2.5 rounded-xl bg-brand-cyan/10 text-brand-cyan group-hover:bg-brand-cyan group-hover:text-black transition-all">
                      {box.icon}
                    </div>
                    <div className="text-sm font-black uppercase tracking-[0.2em] text-white">{box.label}</div>
                  </div>
                  <p className="text-sm leading-relaxed text-slate-500 font-medium">{box.text}</p>
                </div>
              ))}
            </div>
          </div>

          <Card className="rounded-[3.5rem] border border-white/5 p-12 glass-card shadow-2xl relative overflow-hidden group">
            <div className="absolute top-0 right-0 p-12 opacity-5 group-hover:opacity-20 transition-opacity">
              <Sparkles size={160} className="text-brand-cyan" />
            </div>
            
            <div className="mb-10 text-[11px] font-black uppercase tracking-[0.4em] text-brand-cyan flex items-center gap-3">
              <div className="h-2 w-2 rounded-full bg-brand-cyan animate-pulse shadow-[0_0_10px_#00f2fe]" />
              Threat Intelligence Engine
            </div>

            <div className="space-y-10">
              {[
                { title: "Protocol Guards", desc: "Specialized logic for Camelot, SaucerSwap, and more." },
                { title: "Calldata Audit", desc: "Heuristic analysis of function selectors and parameters." },
                { title: "Risk Scoring", desc: "Consolidated security report before wallet interaction." }
              ].map((item, i) => (
                <div key={i} className="flex items-start gap-8">
                  <div className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-brand-cyan/5 font-black text-brand-cyan border border-brand-cyan/10 group-hover:bg-brand-cyan/20 group-hover:border-brand-cyan/40 transition-all text-lg">
                    0{i+1}
                  </div>
                  <div>
                    <div className="text-base font-black text-white uppercase tracking-wider mb-2">{item.title}</div>
                    <p className="text-sm text-slate-500 leading-relaxed font-medium">
                      {item.desc}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        </section>

        {/* ECOSYSTEM COVERAGE */}
        <section className="mb-48">
          <div className="mb-20 text-center space-y-4">
            <h2 className="text-4xl md:text-5xl font-black uppercase tracking-tight text-white leading-tight">Supported Networks</h2>
            <div className="h-1 w-24 bg-brand-cyan mx-auto" />
          </div>

          <div className="grid gap-10 md:grid-cols-2">
            {SUPPORTED_DEXES.map((dex) => (
              <Card key={dex.id} className="group rounded-[3rem] border border-white/5 p-12 glass-card relative overflow-hidden transition-all duration-500 hover:border-brand-cyan/40">
                <div className="absolute -right-20 -top-20 h-64 w-64 rounded-full bg-brand-cyan/5 blur-[80px] group-hover:bg-brand-cyan/10 transition-all" />
                
                <div className="mb-10 flex items-start justify-between gap-6">
                  <div>
                    <div className="text-[10px] font-black uppercase tracking-[0.4em] text-brand-cyan/60">{dex.chain} Network</div>
                    <h3 className="mt-4 text-4xl font-black uppercase tracking-[0.05em] text-white group-hover:text-brand-cyan transition-colors">{dex.name}</h3>
                  </div>
                  <Badge label={dex.network} tone="info" className="bg-brand-cyan/10 border-brand-cyan/20 px-5 py-2 text-[10px]" />
                </div>

                <p className="text-lg leading-relaxed text-slate-400 font-medium mb-12">
                  {dex.description}
                </p>

                <div className="pt-10 border-t border-white/5 flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]" />
                    <span className="text-xs font-bold uppercase tracking-widest text-slate-500">{dex.status}</span>
                  </div>
                  <a 
                    className="flex items-center gap-2 text-xs font-black uppercase tracking-widest text-brand-cyan hover:gap-4 transition-all" 
                    href={dex.website} target="_blank" rel="noreferrer"
                  >
                    Deploy Protection <ArrowRight size={16} />
                  </a>
                </div>
              </Card>
            ))}
          </div>
        </section>

        {/* FINAL CTA */}
        <section className="relative overflow-hidden rounded-[5rem] border border-brand-cyan/10 bg-gradient-to-br from-brand-cyan/5 via-brand-dark to-brand-cyan/5 p-20 md:p-32 text-center">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(0,242,254,0.1),transparent_70%)] pointer-events-none" />
          
          <Logo className="h-32 w-32 mx-auto mb-12 opacity-30" animated={false} />
          
          <h2 className="text-5xl md:text-7xl font-black uppercase tracking-tight text-white mb-8">Defend Your Intent.</h2>
          <p className="mx-auto max-w-2xl text-xl leading-relaxed text-slate-400 font-medium mb-16">
            Join the PreFlight network and secure your DeFi workflow with the industry's first pre-transaction security layer.
          </p>
          
          <div className="flex flex-col items-center justify-center gap-8 sm:flex-row">
            <Button onClick={onOpenInstall} className="w-full sm:w-auto px-16 py-6 text-base font-black uppercase tracking-widest shadow-[0_0_50px_rgba(0,242,254,0.2)]">
              Get Started Now
            </Button>
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full sm:w-auto px-16 py-6 text-base font-black uppercase tracking-widest border-white/10 hover:bg-white/5">
              Protocol View
            </Button>
          </div>
        </section>
      </motion.div>
    </>
  );
}
