import React, { useState, useEffect } from 'react';
import LandingSection from './components/LandingSection';
import Sidebar from './components/Sidebar';
import FloatingIcon from './components/FloatingIcon';

export default function App() {
  const [isLaunched, setIsLaunched] = useState(false);
  const [isSidebarOpen, setSidebarOpen] = useState(false);
  const [currentUrl, setCurrentUrl] = useState("https://app.camelot.exchange");

  // This ensures the security layer stays active "on top" of the DEX
  return (
    <div className="relative min-h-screen bg-[#080808] text-slate-200 overflow-hidden font-sans">
      {!isLaunched ? (
        <LandingSection onLaunch={() => setIsLaunched(true)} />
      ) : (
        <div className="relative w-full h-screen">
          {/* THE PERSISTENT DAPP VIEWER */}
          <div className="absolute inset-0 z-0">
             <div className="absolute top-0 left-0 right-0 h-12 bg-[#111] border-b border-white/10 flex items-center px-4 gap-4 z-50">
                <div className="flex gap-1.5">
                  <div className="w-3 h-3 rounded-full bg-red-500/50" />
                  <div className="w-3 h-3 rounded-full bg-yellow-500/50" />
                  <div className="w-3 h-3 rounded-full bg-green-500/50" />
                </div>
                <div className="bg-black/50 px-4 py-1 rounded-md border border-white/5 text-xs text-slate-400 w-full max-w-md font-mono">
                  {currentUrl}
                </div>
                <div className="ml-auto flex items-center gap-2">
                   <div className="w-2 h-2 rounded-full bg-cyan-500 animate-pulse" />
                   <span className="text-[10px] font-bold text-cyan-500 uppercase tracking-widest">PreFlight Active</span>
                </div>
             </div>
             {/* The DEX Content */}
             <iframe 
                src={currentUrl} 
                className="w-full h-full pt-12 border-none" 
                title="DEX View"
             />
          </div>

          {/* THE PERMANENT SECURITY LAYER */}
          <FloatingIcon 
            isOpen={isSidebarOpen} 
            onClick={() => setSidebarOpen(true)} 
          />
          
          <Sidebar 
            isOpen={isSidebarOpen} 
            onClose={() => setSidebarOpen(false)} 
          />
        </div>
      )}
    </div>
  );
}