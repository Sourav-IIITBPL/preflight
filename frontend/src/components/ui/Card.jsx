import React from 'react';

export default function Card({ children, className = '' }) {
  return <div className={`glass-card rounded-[1.75rem] ${className}`}>{children}</div>;
}
