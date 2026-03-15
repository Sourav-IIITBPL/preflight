import React from 'react';
import { motion } from 'framer-motion';
import {
  ArrowRight,
  ShieldCheck,
  Layers,
  Sparkles
} from 'lucide-react';
import { SUPPORTED_DEXES } from '../constants';
import Button from './ui/Button';
import Card from './ui/Card';
import Badge from './ui/Badge';
import Logo from './ui/Logo';

export default function LandingSection({ onOpenInstall, onOpenPortfolio }) {
  return (
    <>
      {/* Static Background Glow */}
      <div className="fixed inset-0 z-0 pointer-events-none flex items-center justify-center">
        <div className="w-[100vw] h-[100vw] bg-brand-cyan/[0.02] rounded-full blur-[180px]" />
      </div>

      <div className="relative z-10 mx-auto max-w-6xl px-6 py-24">
        <section className="mb-48 pt-20 text-center flex flex-col items-center">
          {/* Centered MASSIVE Professional Logo - THE ONLY DYNAMIC ELEMENT */}
          <div className="mb-12 relative">
            <div className="absolute inset-0 bg-brand-cyan/20 blur-[120px] rounded-full scale-125" />
            <div className="absolute inset-0 bg-brand-cyan/5 blur-[40px] rounded-full" />
            
            <Logo className="h-80 w-80 md:h-[32rem] md:w-[32rem] text-brand-cyan" animated={true} />
          </div>

          <p className="mx-auto mt-8 max-w-4xl text-xl font-medium leading-relaxed text-slate-400 md:text-2xl">
            The <span className="text-white font-bold italic">Zero-Trust Interceptor</span> for Modern DeFi.
            Verify intent before you sign. Execute through explainable security guards.
          </p>

          <div className="mt-16 flex flex-col items-center justify-center gap-6 sm:flex-row w-full max-w-lg">
            <Button onClick={onOpenInstall} className="w-full sm:w-auto px-12 py-5 text-sm shadow-[0_0_60px_rgba(0,242,254,0.3)]">
              Secure Chrome <ArrowRight size={18} />
            </Button>
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full sm:w-auto px-12 py-5 text-sm border-white/10 hover:bg-white/5">
              Protocol Dashboard
            </Button>
          </div>
        </section>

        {/* Value Proposition - Static */}
        <section className="mb-40 grid gap-12 md:grid-cols-2 md:items-center">
          <div className="space-y-8 text-left">
            <h2 className="text-4xl font-black uppercase tracking-tight text-white leading-tight">Interception-at-Origin</h2>
            <p className="text-lg leading-relaxed text-slate-400 font-medium">
              Don't trust wallet previews. PreFlight runs inside the official DEX runtime, capturing 
              the real transaction intent before it even hits your wallet. We decode the exact 
              calldata, paths, and amounts to give you the truth.
            </p>
            <div className="grid gap-6">
              {[
                { label: "Trust Isolation", text: "Verified execution outside the DEX's own logic boundaries.", icon: <ShieldCheck size={20} /> },
                { label: "Evidence Chains", text: "Every verdict is immutable evidence on the Arbitrum network.", icon: <Layers size={20} /> }
              ].map((box, i) => (
                <div 
                  key={i}
                  className="rounded-3xl border border-white/10 bg-white/[0.03] p-6"
                >
                  <div className="flex items-center gap-4 mb-3">
                    <div className="p-2 rounded-xl bg-brand-cyan/10 text-brand-cyan">
                      {box.icon}
                    </div>
                    <div className="text-sm font-black uppercase tracking-[0.2em] text-white">{box.label}</div>
                  </div>
                  <p className="text-sm leading-relaxed text-slate-400">{box.text}</p>
                </div>
              ))}
            </div>
          </div>

          <Card className="rounded-[3rem] border border-white/10 p-10 glass-card shadow-2xl relative">
            <div className="absolute top-0 right-0 p-10 opacity-5">
              <Sparkles size={120} className="text-brand-cyan" />
            </div>
            <div className="mb-8 text-[11px] font-black uppercase tracking-[0.3em] text-brand-cyan flex items-center gap-2">
              <div className="h-1.5 w-1.5 rounded-full bg-brand-cyan animate-pulse" />
              Runtime Intelligence
            </div>
            <div className="space-y-6">
              {[
                "DEX Interception Layer",
                "Heuristic & CRE Simulation",
                "Router-Gated Settlement"
              ].map((text, i) => (
                <React.Fragment key={i}>
                  <div className="flex items-start gap-6">
                    <div className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-brand-cyan/10 font-black text-brand-cyan border border-brand-cyan/20">
                      0{i+1}
                    </div>
                    <div>
                      <div className="text-sm font-black text-white uppercase tracking-wider mb-1">{text}</div>
                      <p className="text-xs text-slate-500 leading-relaxed">
                        {i === 0 && "Capture raw intent on Camelot, SaucerSwap, and more."}
                        {i === 1 && "Run off-chain checks and on-chain guard validations."}
                        {i === 2 && "Final signature only happens after the report is accepted."}
                      </p>
                    </div>
                  </div>
                  {i < 2 && <div className="ml-5 h-10 w-px bg-brand-cyan/20" />}
                </React.Fragment>
              ))}
            </div>
          </Card>
        </section>

        {/* Coverage - Static */}
        <section className="mb-40">
          <div className="mb-16 text-center">
            <h2 className="text-4xl font-black uppercase tracking-tight text-white">Institutional Coverage</h2>
            <p className="mt-4 text-slate-500 font-medium uppercase tracking-widest text-xs">Standardized across major liquidity networks</p>
          </div>

          <div className="grid gap-8 md:grid-cols-2">
            {SUPPORTED_DEXES.map((dex) => (
              <Card key={dex.id} className="group rounded-[2.5rem] border border-white/5 p-10 glass-card relative overflow-hidden">
                <div className="mb-8 flex items-start justify-between gap-4">
                  <div>
                    <div className="text-[10px] font-black uppercase tracking-[0.25em] text-brand-cyan/60">{dex.chain}</div>
                    <h3 className="mt-3 text-3xl font-black uppercase tracking-[0.05em] text-white">{dex.name}</h3>
                  </div>
                  <Badge label={dex.network} tone="info" className="bg-brand-cyan/10 border-brand-cyan/20 px-4 py-1.5" />
                </div>
                <p className="text-base leading-relaxed text-slate-400 font-medium">{dex.description}</p>
                <div className="mt-8 pt-8 border-t border-white/5 flex items-center justify-between gap-4">
                  <span className="text-xs font-bold uppercase tracking-widest text-slate-600">{dex.status}</span>
                  <a className="flex items-center gap-2 text-xs font-black uppercase tracking-widest text-brand-cyan" href={dex.website} target="_blank" rel="noreferrer">
                    Launch <ArrowRight size={14} />
                  </a>
                </div>
              </Card>
            ))}
          </div>
        </section>

        {/* Final CTA - Static */}
        <section className="relative overflow-hidden rounded-[4rem] border border-brand-cyan/20 bg-brand-dark p-16 md:p-24 text-center">
          <Logo className="h-24 w-24 mx-auto mb-10 opacity-20" animated={false} />
          <h2 className="text-5xl font-black uppercase tracking-tight text-white md:text-6xl">Defend Your Capital.</h2>
          <p className="mx-auto mt-8 max-w-2xl text-lg leading-relaxed text-slate-400 font-medium">
            Join the PreFlight network today. Secure your DeFi workflow with our intelligent interception layer and Arbitrum-backed evidence.
          </p>
          <div className="mt-12 flex flex-col items-center justify-center gap-6 sm:flex-row">
            <Button onClick={onOpenInstall} className="w-full sm:w-auto px-16 py-6 text-base font-black uppercase tracking-widest shadow-2xl">
              Get Started
            </Button>
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full sm:w-auto px-16 py-6 text-base font-black uppercase tracking-widest border-white/10">
              Dashboard
            </Button>
          </div>
        </section>
      </div>
    </>
  );
}
