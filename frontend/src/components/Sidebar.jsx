import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, ShieldCheck, Zap, BarChart3, ChevronRight, Info } from 'lucide-react';
import RiskShield from './RiskShield';

export default function Sidebar({ isOpen, onClose }) {
  const [status, setStatus] = useState('idle'); // idle -> checking -> report
  
  // Simulation of reading the page inputs
  const pageData = {
    action: "Swap",
    protocol: "Camelot V3",
    pair: "WETH / USDC",
    amount: "2.5 ETH"
  };

  const handleCheck = () => {
    setStatus('checking');
    setTimeout(() => setStatus('report'), 1800);
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div 
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-[110]"
          />
          
          {/* Sidebar Content */}
          <motion.div 
            initial={{ x: '100%' }} animate={{ x: 0 }} exit={{ x: '100%' }}
            transition={{ type: 'spring', damping: 25, stiffness: 200 }}
            className="fixed top-0 right-0 w-[420px] h-full glass-card z-[120] flex flex-col shadow-2xl border-l border-[#00F2FE]/20"
          >
            {/* Header */}
            <div className="p-6 border-b border-white/5 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-lg bg-[#00F2FE]/10 flex items-center justify-center border border-[#00F2FE]/30">
                  <ShieldCheck size={18} className="text-[#00F2FE]" />
                </div>
                <h2 className="text-xl font-bold tracking-tight">Security Check</h2>
              </div>
              <button onClick={onClose} className="p-2 hover:bg-white/5 rounded-full text-gray-500 hover:text-white transition-all">
                <X size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-8">
              {/* Context Section */}
              <div className="space-y-4">
                <h3 className="text-[10px] font-black uppercase tracking-widest text-[#00F2FE]/60">Transaction Context</h3>
                <div className="bg-white/5 rounded-xl p-4 border border-white/5">
                  <div className="flex justify-between items-start mb-3">
                    <span className="text-sm text-gray-400">Target Protocol</span>
                    <span className="text-sm font-bold text-white">{pageData.protocol}</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-2xl font-black text-white">{pageData.amount}</span>
                    <ChevronRight className="text-gray-600" />
                    <span className="text-sm font-medium text-gray-400">{pageData.pair}</span>
                  </div>
                </div>
              </div>

              {/* Analysis Section */}
              {status === 'idle' && (
                <button 
                  onClick={handleCheck}
                  className="w-full py-4 bg-[#00F2FE] hover:bg-[#00D7E1] text-black font-black rounded-xl transition-all neon-glow flex items-center justify-center gap-2"
                >
                  <Zap size={18} fill="black" /> RUN PRE-FLIGHT
                </button>
              )}

              {status === 'checking' && (
                <div className="text-center py-12 space-y-4">
                  <div className="w-12 h-12 border-2 border-[#00F2FE]/20 border-t-[#00F2FE] rounded-full animate-spin mx-auto" />
                  <p className="text-sm font-mono text-[#00F2FE] animate-pulse uppercase tracking-widest">Verifying State Invariants...</p>
                </div>
              )}

              {status === 'report' && (
                <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
                  <RiskShield score={98} />
                  
                  <div className="space-y-3">
                    <h3 className="text-[10px] font-black uppercase tracking-widest text-gray-500">Security Flags</h3>
                    {[
                      { label: "Token Guard", status: "Verified", detail: "Allowlist Match" },
                      { label: "Swap Guard", status: "Verified", detail: "Slippage < 0.5%" },
                      { label: "Vault Guard", status: "Optimal", detail: "No flash imbalances" }
                    ].map((item, i) => (
                      <div key={i} className="flex items-center justify-between p-3 rounded-lg bg-white/[0.02] border border-white/5">
                        <div className="flex flex-col">
                          <span className="text-xs font-bold text-white">{item.label}</span>
                          <span className="text-[10px] text-gray-500">{item.detail}</span>
                        </div>
                        <span className="text-[10px] px-2 py-1 rounded bg-green-500/10 text-green-400 font-bold border border-green-500/20 uppercase">Passed</span>
                      </div>
                    ))}
                  </div>

                  <div className="pt-4 border-t border-white/5 space-y-3">
                    <button className="w-full py-3 bg-white/5 hover:bg-white/10 text-white text-xs font-bold rounded-lg border border-white/10 transition-all uppercase tracking-widest">
                      Mint On-Chain SVG Report
                    </button>
                    <button className="w-full py-4 bg-green-600 hover:bg-green-500 text-white font-black rounded-xl transition-all uppercase tracking-widest">
                      Execute Transaction
                    </button>
                  </div>
                </motion.div>
              )}
            </div>
            
            <div className="p-4 bg-black/40 border-t border-white/5 flex items-center justify-center gap-2">
               <div className="w-1.5 h-1.5 rounded-full bg-green-500 shadow-[0_0_5px_#22c55e]"></div>
               <span className="text-[9px] font-bold text-gray-500 uppercase tracking-[0.3em]">Arbitrum One Mainnet Active</span>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}