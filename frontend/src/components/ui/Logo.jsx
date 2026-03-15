import React from 'react';
import { motion } from 'framer-motion';

export default function Logo({ className = "h-10 w-10", animated = false, intensity = "full" }) {
  const opacityClass = intensity === "low" ? "opacity-5" : "opacity-100";
  
  const pathVariants = {
    hidden: { pathLength: 0, opacity: 0 },
    visible: { 
      pathLength: 1, 
      opacity: 0.4,
      transition: { 
        duration: 2, 
        ease: "easeInOut",
        repeat: animated ? Infinity : 0,
        repeatType: "reverse"
      }
    }
  };

  return (
    <motion.div 
      className={`relative flex items-center justify-center ${className} ${opacityClass}`}
      initial="hidden"
      animate="visible"
    >
      {/* Dynamic Glow Background */}
      <div className="absolute inset-0 bg-brand-cyan/5 blur-3xl rounded-full scale-125" />
      
      {/* Animated SVG Frame / HUD - Embedded truly as professional sign */}
      <svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" className="absolute inset-0 w-full h-full z-10">
        {/* Outer Hexagon Trace */}
        <motion.path 
          d="M50 5L92 27V73L50 95L8 73V27L50 5Z" 
          stroke="currentColor" 
          strokeWidth="0.5" 
          className="text-brand-cyan/20"
          variants={pathVariants}
        />
        
        {/* Corner Accents */}
        <motion.path 
          d="M20 15L10 20V30M80 15L90 20V30M20 85L10 80V70M80 85L90 80V70" 
          stroke="currentColor" 
          strokeWidth="1" 
          className="text-brand-cyan/40"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1, duration: 1 }}
        />
      </svg>

      {/* The Provided Logo SVG (Embedded PNG) */}
      <motion.div 
        className="relative z-20 w-[75%] h-[75%] flex items-center justify-center"
        animate={animated ? {
          filter: ["drop-shadow(0 0 10px rgba(0,242,254,0.2))", "drop-shadow(0 0 20px rgba(0,242,254,0.4))", "drop-shadow(0 0 10px rgba(0,242,254,0.2))"]
        } : {}}
        transition={{ duration: 4, repeat: Infinity }}
      >
        <img 
          src="/logo.svg" 
          alt="PreFlight" 
          className="w-full h-full object-contain"
          style={{ mixBlendingMode: 'screen' }}
        />
        
        {/* Scanning Line Animation */}
        {animated && (
          <motion.div 
            className="absolute inset-0 w-full bg-gradient-to-b from-transparent via-brand-cyan/10 to-transparent z-30"
            style={{ height: '20%' }}
            animate={{ top: ['-20%', '100%'] }}
            transition={{ duration: 3, repeat: Infinity, ease: "linear" }}
          />
        )}
      </motion.div>
    </motion.div>
  );
}
