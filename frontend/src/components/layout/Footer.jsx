import React from 'react';
import { motion } from 'framer-motion';
import { Github, Twitter, BookOpen, ExternalLink, Shield } from 'lucide-react';
import Logo from '../ui/Logo';

export default function Footer() {
  return (
    <footer className="relative z-10 border-t border-white/5 bg-brand-dark/80 backdrop-blur-md pt-20 pb-10 overflow-hidden">
       {/* Decorative Background */}
       <div className="absolute -bottom-24 -right-24 h-96 w-96 rounded-full bg-brand-cyan/5 blur-[100px] pointer-events-none" />
       
       <div className="mx-auto max-w-7xl px-6">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-20">
             {/* Brand */}
             <div className="md:col-span-2 space-y-6">
                <div className="flex items-center gap-4">
                   <Logo className="h-10 w-10" animated={false} />
                   <span className="text-2xl font-black uppercase tracking-widest text-white">PreFlight</span>
                </div>
                <p className="text-slate-500 max-w-sm leading-relaxed text-sm font-medium">
                   The first pre-transaction security layer for DeFi. Intercept, simulate, and validate your intent before it hits the chain.
                </p>
                <div className="flex gap-4">
                   <a href="https://github.com/Sourav-IIITBPL/preflight" target="_blank" rel="noreferrer" className="p-3 rounded-xl bg-white/5 text-slate-400 hover:text-brand-cyan hover:bg-brand-cyan/10 transition-all border border-white/5">
                      <Github size={20} />
                   </a>
                   <a href="#" className="p-3 rounded-xl bg-white/5 text-slate-400 hover:text-brand-cyan hover:bg-brand-cyan/10 transition-all border border-white/5">
                      <Twitter size={20} />
                   </a>
                </div>
             </div>

             {/* Links */}
             <div>
                <h4 className="text-white font-black uppercase tracking-widest text-sm mb-6">Resources</h4>
                <ul className="space-y-4">
                   <li>
                      <a href="https://github.com/Sourav-IIITBPL/preflight" target="_blank" rel="noreferrer" className="text-slate-500 hover:text-brand-cyan text-sm font-bold flex items-center gap-2 transition-colors">
                         <BookOpen size={14} /> Documentation
                      </a>
                   </li>
                   <li>
                      <a href="https://github.com/Sourav-IIITBPL/preflight" target="_blank" rel="noreferrer" className="text-slate-500 hover:text-brand-cyan text-sm font-bold flex items-center gap-2 transition-colors">
                         <Github size={14} /> GitHub Source
                      </a>
                   </li>
                </ul>
             </div>

             {/* Safety */}
             <div>
                <h4 className="text-white font-black uppercase tracking-widest text-sm mb-6">Security</h4>
                <div className="p-4 rounded-2xl bg-brand-cyan/5 border border-brand-cyan/10 space-y-3">
                   <div className="flex items-center gap-2 text-brand-cyan">
                      <Shield size={16} />
                      <span className="text-[10px] font-black uppercase tracking-widest">Pre-Execution Guard</span>
                   </div>
                   <p className="text-[10px] text-slate-500 font-medium leading-relaxed">
                      All simulation logic is deterministic and open-source for public verification.
                   </p>
                </div>
             </div>
          </div>

          {/* Bottom */}
          <div className="pt-10 border-t border-white/5 flex flex-col md:flex-row justify-between gap-6 items-center">
             <div className="text-[10px] font-bold text-slate-600 uppercase tracking-[0.2em]">
                © {new Date().getFullYear()} Preflight Labs. All Rights Reserved.
             </div>
             <div className="flex gap-8 text-[10px] font-bold text-slate-600 uppercase tracking-[0.2em]">
                <a href="#" className="hover:text-slate-400 transition-colors">Privacy Policy</a>
                <a href="#" className="hover:text-slate-400 transition-colors">Terms of Service</a>
             </div>
             <div className="text-[10px] font-medium text-slate-500 italic max-w-xs text-center md:text-right">
                Disclaimer: PreFlight provides transaction risk analysis but does not guarantee absolute protection.
             </div>
          </div>
       </div>
    </footer>
  );
}
