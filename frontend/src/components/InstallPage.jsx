import React, { useMemo } from 'react';
import { CheckCircle2, Chrome, Copy, Monitor, Puzzle, ShieldCheck, Wallet } from 'lucide-react';
import { COMPATIBILITY_NOTES, INSTALL_STEPS, SUPPORTED_DEXES } from '../constants';
import Button from './ui/Button';
import Card from './ui/Card';
import Badge from './ui/Badge';

function getExtensionStatus() {
  const extensionId = import.meta.env.VITE_PREFLIGHT_EXTENSION_ID ?? '';
  if (!extensionId) return { label: 'Demo mode', tone: 'warning', detail: 'No extension ID configured yet. Use unpacked install flow.' };
  return { label: 'Config ready', tone: 'info', detail: `Extension ID configured: ${extensionId}` };
}

export default function InstallPage({ onOpenPortfolio }) {
  const extensionStatus = useMemo(() => getExtensionStatus(), []);

  return (
    <section className="space-y-8">
      <Card className="overflow-hidden border border-white/10 p-8 md:p-10">
        <div className="grid gap-8 lg:grid-cols-[1fr_320px] lg:items-start">
          <div>
            <p className="text-[10px] font-black uppercase tracking-[0.22em] text-brand-cyan">Install guide</p>
            <h1 className="mt-3 text-4xl font-black uppercase tracking-[0.08em] text-white">Run PreFlight as a browser layer</h1>
            <p className="mt-4 max-w-3xl text-sm leading-relaxed text-slate-400">
              The demo path is Chrome unpacked extension install. After loading the extension, users pin it, activate it on Camelot or SaucerSwap,
              then continue using the official DEX while PreFlight handles verification and reporting around the real transaction request.
            </p>
            <div className="mt-6 flex flex-wrap items-center gap-3">
              <Badge label={extensionStatus.label} tone={extensionStatus.tone} />
              <span className="text-xs text-slate-400">{extensionStatus.detail}</span>
            </div>
          </div>

          <div className="rounded-[1.75rem] border border-brand-cyan/20 bg-brand-cyan/5 p-6">
            <div className="text-[10px] font-black uppercase tracking-[0.18em] text-brand-cyan">Demo targets</div>
            <div className="mt-4 space-y-3 text-sm text-slate-300">
              <div className="flex items-center justify-between"><span>Browser</span><span>Chrome / Brave</span></div>
              <div className="flex items-center justify-between"><span>DEXs</span><span>Camelot + SaucerSwap</span></div>
              <div className="flex items-center justify-between"><span>Execution</span><span>Official DEX + PreFlightRouter</span></div>
            </div>
          </div>
        </div>
      </Card>

      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {INSTALL_STEPS.map((item) => (
          <Card key={item.step} className="p-6 hover-reveal">
            <div className="text-[10px] font-black uppercase tracking-[0.18em] text-brand-cyan">Step {item.step}</div>
            <h2 className="mt-3 text-lg font-black uppercase tracking-[0.08em] text-white">{item.title}</h2>
            <p className="mt-3 text-sm leading-relaxed text-slate-400">{item.body}</p>
          </Card>
        ))}
      </section>

      <section className="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
        <Card className="p-8">
          <h2 className="text-2xl font-black uppercase tracking-[0.08em] text-white">Chrome unpacked checklist</h2>
          <div className="mt-6 space-y-4 text-sm text-slate-300">
            {[
              ['Download extension build', 'Get the packaged extension folder from the PreFlight project output.'],
              ['Open extension settings', 'Visit chrome://extensions and enable Developer mode.'],
              ['Load unpacked', 'Choose the extension build directory and confirm install.'],
              ['Pin PreFlight', 'Pin the extension so activation is easy on supported DEX pages.'],
            ].map(([title, body]) => (
              <div key={title} className="flex items-start gap-3 rounded-2xl border border-white/8 bg-white/[0.03] p-4">
                <CheckCircle2 size={16} className="mt-0.5 text-brand-cyan" />
                <div>
                  <div className="font-bold text-white">{title}</div>
                  <div className="mt-1 text-slate-400">{body}</div>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-8">
          <h2 className="text-2xl font-black uppercase tracking-[0.08em] text-white">What users should expect on the DEX page</h2>
          <div className="mt-6 grid gap-4 md:grid-cols-2">
            {[
              { icon: <Puzzle size={16} />, title: 'Floating launcher', body: 'The extension adds a floating PreFlight control on supported DEX pages after activation.' },
              { icon: <Wallet size={16} />, title: 'Real wallet context', body: 'MetaMask or the live wallet flow stays on the official DEX, which is exactly what PreFlight needs to observe.' },
              { icon: <ShieldCheck size={16} />, title: 'Chronological checks', body: 'Users see transaction interception, CRE verification, on-chain reads, and the final verdict in order.' },
              { icon: <Monitor size={16} />, title: 'Centered report view', body: 'The result appears as a closable report layer with mint and execute actions.' },
            ].map((item) => (
              <div key={item.title} className="rounded-2xl border border-white/8 bg-white/[0.03] p-4">
                <div className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-brand-cyan/20 bg-brand-cyan/10 text-brand-cyan">
                  {item.icon}
                </div>
                <div className="mt-3 font-bold uppercase tracking-[0.08em] text-white">{item.title}</div>
                <p className="mt-2 text-sm leading-relaxed text-slate-400">{item.body}</p>
              </div>
            ))}
          </div>
        </Card>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <Card className="p-8">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 className="text-2xl font-black uppercase tracking-[0.08em] text-white">Supported browsers and networks</h2>
              <p className="mt-2 text-sm text-slate-400">The website stays chain-agnostic for guidance, while the extension carries protocol-specific adapters.</p>
            </div>
            <Badge label="Demo release" tone="info" />
          </div>

          <div className="mt-6 grid gap-4 md:grid-cols-2">
            {SUPPORTED_DEXES.map((dex) => (
              <div key={dex.id} className="rounded-2xl border border-white/8 bg-white/[0.03] p-5">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <div className="text-[10px] font-black uppercase tracking-[0.18em] text-brand-cyan">{dex.chain}</div>
                    <div className="mt-2 text-lg font-black uppercase tracking-[0.08em] text-white">{dex.name}</div>
                  </div>
                  <Chrome size={18} className="text-slate-500" />
                </div>
                <p className="mt-3 text-sm leading-relaxed text-slate-400">{dex.website}</p>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-8">
          <h2 className="text-2xl font-black uppercase tracking-[0.08em] text-white">Compatibility notes</h2>
          <div className="mt-6 space-y-3">
            {COMPATIBILITY_NOTES.map((note) => (
              <div key={note} className="flex items-start gap-3 rounded-2xl border border-white/8 bg-white/[0.03] p-4 text-sm text-slate-400">
                <Copy size={14} className="mt-0.5 text-brand-cyan" />
                <span>{note}</span>
              </div>
            ))}
          </div>

          <div className="mt-8">
            <Button variant="ghost" onClick={onOpenPortfolio} className="w-full justify-center py-3">
              Open Portfolio After Install
            </Button>
          </div>
        </Card>
      </section>
    </section>
  );
}
