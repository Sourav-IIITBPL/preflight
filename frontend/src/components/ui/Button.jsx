import React from 'react';

export default function Button({
  children,
  variant = 'primary',
  className = '',
  disabled = false,
  ...props
}) {
  const base = 'inline-flex items-center justify-center gap-2 disabled:cursor-not-allowed disabled:opacity-60';
  const variants = {
    primary: 'btn-primary px-4 py-2 text-[11px]',
    ghost: 'btn-outline px-4 py-2 text-[11px]',
  };

  return (
    <button className={`${base} ${variants[variant] ?? variants.primary} ${className}`} disabled={disabled} {...props}>
      {children}
    </button>
  );
}
