import React from 'react';
import { motion } from 'framer-motion';
import { Shield } from 'lucide-react';

export default function FloatingIcon({ onClick, isOpen }) {
  if (isOpen) return null;

  return (
    <motion.div 
      initial={{ scale: 0, opacity: 0 }}
      animate={{ scale: 1, opacity: 1 }}
      whileHover={{ scale: 1.05 }}
      onClick={onClick}
      className="fixed bottom-8 right-8 z-[100] cursor-pointer"
    >
      <div className="relative flex items-center gap-3 bg-[#00F2FE] text-black px-6 py-3 rounded-full font-bold shadow-[0_0_20px_rgba(0,242,254,0.4)]">
        <Shield size={20} fill="black" />
        <span>PreFlight</span>
        <span className="bg-red-500 text-white text-[10px] px-1.5 py-0.5 rounded-md absolute -top-1 -right-1">1</span>
      </div>
      {/* Pulsing Aura */}
      <div className="absolute inset-0 bg-[#00F2FE] rounded-full animate-ping opacity-20 -z-10"></div>
    </motion.div>
  );
}