import React from 'react';
import { motion } from 'framer-motion';

export default function RiskShield({ score }) {
  // Calculate stroke-dasharray based on score (0-100)
  const radius = 45;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (score / 100) * circumference;

  const getScoreColor = (s) => {
    if (s > 80) return "#00F2FE";
    if (s > 50) return "#fbbf24";
    return "#ef4444";
  };

  return (
    <div className="relative flex flex-col items-center justify-center p-6 bg-white/[0.03] rounded-3xl border border-white/5">
      <div className="relative w-40 h-40">
        <svg className="w-full h-full transform -rotate-90">
          {/* Background Circle */}
          <circle
            cx="80" cy="80" r={radius}
            stroke="currentColor" strokeWidth="8"
            fill="transparent" className="text-white/5"
          />
          {/* Progress Circle */}
          <motion.circle
            cx="80" cy="80" r={radius}
            stroke={getScoreColor(score)} strokeWidth="8"
            fill="transparent"
            strokeDasharray={circumference}
            initial={{ strokeDashoffset: circumference }}
            animate={{ strokeDashoffset: offset }}
            transition={{ duration: 1.5, ease: "easeOut" }}
            strokeLinecap="round"
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-4xl font-black text-white">{score}</span>
          <span className="text-[10px] font-bold text-gray-500 uppercase tracking-widest">Integrity</span>
        </div>
      </div>
      
      <div className="mt-4 w-full px-4">
        <div className="flex justify-between text-[10px] font-bold uppercase tracking-tighter mb-1">
          <span className="text-gray-500">Risk Level</span>
          <span style={{ color: getScoreColor(score) }}>
            {score > 80 ? 'Low Risk' : score > 50 ? 'Medium Risk' : 'Critical'}
          </span>
        </div>
        <div className="h-1 w-full bg-white/5 rounded-full overflow-hidden">
          <motion.div 
            initial={{ width: 0 }}
            animate={{ width: `${score}%` }}
            className="h-full"
            style={{ backgroundColor: getScoreColor(score) }}
          />
        </div>
      </div>
    </div>
  );
}