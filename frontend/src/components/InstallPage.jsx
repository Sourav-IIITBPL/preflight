import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Download,
  Wallet,
  Shield,
  MousePointer2,
  CheckCircle2,
  ArrowRight,
  ExternalLink,
  Play
} from 'lucide-react';
import { 
  INSTALL_STEPS, 
  WORKFLOW_STEPS, 
  SUPPORTED_DEXES, 
  SUPPORTED_VAULTS,
  YT_DEMO_URL,
  COMPATIBILITY_NOTES
} from '../constants';
import Button from './ui/Button';
import Card from './ui/Card';

const LogoSlider = ({ items }) => {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setIndex((prev) => (prev + 1) % items.length);
    }, 2000);
    return () => clearInterval(timer);
  }, [items.length]);

  return (
    <div className="relative h-48 w-full overflow-hidden rounded-2xl glass-card">
       <AnimatePresence mode="wait">
          <motion.div
            key={index}
            initial={{ x: 300, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: -300, opacity: 0 }}
            transition={{ duration: 0.5, ease: "easeInOut" }}
            className="absolute inset-0 flex flex-col items-center justify-center p-6"
          >
             <div className="w-20 h-20 mb-4 relative">
                <img src={items[index].logo} alt={items[index].name} className="w-full h-full object-contain filter drop-shadow-[0_0_10px_rgba(255,255,255,0.2)]" />
             </div>
             <div className="text-white font-black uppercase tracking-widest text-sm">{items[index].name}</div>
          </motion.div>
       </AnimatePresence>
    </div>
  );
};

export default function InstallPage({ onOpenPortfolio }) {
  return (
    <div className="max-w-6xl mx-auto px-6 py-20">
      {/* HEADER */}
      <section className="text-center mb-20">
         <motion.h1 
           initial={{ opacity: 0, y: 20 }}
           animate={{ opacity: 1, y: 0 }}
           className="text-5xl md:text-7xl font-black text-white uppercase mb-6"
         >
           Get Started with <span className="gradient-text">PreFlight</span>
         </motion.h1>
         <p className="text-xl text-slate-400 font-cursive">Your journey to secure DeFi starts here.</p>
      </section>

      <div className="grid lg:grid-cols-2 gap-20">
         {/* INSTALLATION STEPS */}
         <div className="space-y-12">
            <h2 className="text-3xl font-black text-white uppercase flex items-center gap-4">
               <Download className="text-brand-cyan" /> Installation Steps
            </h2>
            <div className="space-y-6">
               {INSTALL_STEPS.map((step, i) => (
                 <div key={i} className="flex gap-6 group">
                    <div className="shrink-0 w-12 h-12 rounded-xl bg-brand-cyan/10 border border-brand-cyan/20 flex items-center justify-center text-brand-cyan font-black group-hover:bg-brand-cyan group-hover:text-black transition-all">
                       {step.step}
                    </div>
                    <div>
                       <h3 className="text-xl font-bold text-white mb-2">{step.title}</h3>
                       <p className="text-slate-400 text-sm leading-relaxed">{step.body}</p>
                    </div>
                 </div>
               ))}
            </div>
         </div>

         {/* USER EXECUTION FLOW */}
         <div className="space-y-12">
            <h2 className="text-3xl font-black text-white uppercase flex items-center gap-4">
               <Shield className="text-brand-cyan" /> Execution Flow
            </h2>
            <Card className="glass-card p-8 border-brand-cyan/10">
               <div className="space-y-6">
                  {WORKFLOW_STEPS.map((step, i) => (
                    <div key={i} className="flex items-start gap-4">
                       <div className="mt-1">
                          <CheckCircle2 size={16} className="text-brand-cyan" />
                       </div>
                       <p className="text-sm text-slate-300 font-medium">{step}</p>
                    </div>
                  ))}
               </div>
            </Card>
         </div>
      </div>

      {/* SUPPORTED PLATFORMS */}
      <section className="mt-32">
         <h2 className="text-4xl font-black text-white uppercase text-center mb-16">Supported Ecosystem</h2>
         <div className="grid md:grid-cols-2 gap-8">
            <div className="space-y-6">
               <div className="text-sm font-black text-brand-cyan uppercase tracking-widest text-center">DEXes & Aggregators</div>
               <LogoSlider items={SUPPORTED_DEXES} />
            </div>
            <div className="space-y-6">
               <div className="text-sm font-black text-brand-cyan uppercase tracking-widest text-center">ERC-4626 Vaults</div>
               <LogoSlider items={SUPPORTED_VAULTS} />
            </div>
         </div>
      </section>

      {/* WATCH DEMO */}
      <section className="mt-32">
         <div className="glass-card rounded-[3rem] p-8 md:p-12 border-brand-cyan/10 overflow-hidden">
            <h2 className="text-3xl font-black text-white uppercase flex items-center gap-4 mb-8">
               <Play className="text-brand-cyan" /> Watch PreFlight in Action
            </h2>
            <div className="relative aspect-video rounded-2xl overflow-hidden bg-slate-900 border border-white/5 shadow-2xl">
               <iframe 
                 src={YT_DEMO_URL}
                 className="absolute inset-0 w-full h-full"
                 title="PreFlight Demo"
                 frameBorder="0"
                 allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                 allowFullScreen
               ></iframe>
            </div>
         </div>
      </section>

      {/* COMPATIBILITY NOTES */}
      <section className="mt-32">
         <div className="grid md:grid-cols-2 gap-12 items-center">
            <div>
               <h2 className="text-3xl font-black text-white uppercase mb-8">Compatibility</h2>
               <div className="space-y-4">
                  {COMPATIBILITY_NOTES.map((note, i) => (
                    <div key={i} className="p-4 glass-card rounded-xl border-white/5 text-sm text-slate-400">
                       {note}
                    </div>
                  ))}
               </div>
            </div>
            <div className="text-center md:text-right space-y-8">
               <div className="font-cursive text-4xl text-brand-cyan">Secure your transactions today.</div>
               <div className="flex flex-col sm:flex-row justify-center md:justify-end gap-6">
                  <Button className="px-12 py-5 uppercase tracking-widest">
                     Install Now <ExternalLink size={18} />
                  </Button>
                  <Button variant="ghost" onClick={onOpenPortfolio} className="px-12 py-5 uppercase tracking-widest">
                     Portfolio View
                  </Button>
               </div>
            </div>
         </div>
      </section>
    </div>
  );
}
