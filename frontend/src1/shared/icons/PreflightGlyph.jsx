import React from 'react';
import { Shield } from 'lucide-react';

export default function PreflightGlyph({ className = 'h-5 w-5' }) {
  return <Shield className={className} strokeWidth={2.2} />;
}
