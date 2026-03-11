import React from 'react';

export default function ExecuteTransactionButton({ onClick, disabled, status = 'idle' }) {
  const label = status === 'pending' ? 'Executing...' : 'Execute Transaction';

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="inline-flex w-full items-center justify-center rounded-xl bg-green-600 px-4 py-3 text-[11px] font-black uppercase tracking-wider text-white transition-all hover:bg-green-500 disabled:cursor-not-allowed disabled:opacity-55"
    >
      {label}
    </button>
  );
}
