import { jsxs, Fragment, jsx } from "react/jsx-runtime";
import React, { useState, useMemo, useEffect, useRef, useCallback } from "react";
import ReactDOM from "react-dom/client";
import { useAccount, useConnect, useDisconnect, createConfig, http, WagmiProvider } from "wagmi";
import { Shield, Activity, ArrowRight, Fingerprint, Layers, Database, Globe, ShieldCheck, Clock3, AlertTriangle, X, Layers2, PanelRightOpen, LoaderCircle, CheckCircle2, CircleX, CircleDashed, Wallet, Link2, FileSearch2, Zap, RefreshCcw, FileText, ShieldAlert, ExternalLink } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import { arbitrum } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
const APP_ROUTES = {
  HOME: "home",
  DEX: "dex",
  PORTFOLIO: "portfolio"
};
const APP_NAME = "PreFlight";
const NETWORK_LABEL = "Arbitrum One";
const REPORT_STALE_AFTER_MS = 1e4;
const TOAST_TTL_MS = 4e3;
const INTENT_CHANNEL = "preflight_intent_channel";
const INTENT_STORAGE_KEY = "preflight.intent.v1";
const REPORT_STORAGE_KEY = "preflight.reports.v1";
const LAUNCH_STORAGE_KEY = "preflight.launch.active.v1";
const DEX_SELECTION_STORAGE_KEY = "preflight.dex.selection.v1";
const SUPPORTED_DEXES = [
  {
    id: "camelot-arbitrum",
    name: "Camelot",
    chain: "Arbitrum",
    url: "https://app.camelot.exchange",
    tag: "Arbitrum Mainnet",
    type: "swap-liquidity"
  },
  {
    id: "saucerswap-hedera",
    name: "SaucerSwap",
    chain: "Hedera",
    url: "https://www.saucerswap.finance",
    tag: "Hedera Mainnet",
    type: "swap-liquidity"
  }
];
function readJsonStorage(key, fallback) {
  try {
    const value = localStorage.getItem(key);
    if (!value) return fallback;
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}
function writeJsonStorage(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
  }
}
function createToast(title, message) {
  return {
    id: `toast_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    title,
    message
  };
}
function findDexById(id) {
  return SUPPORTED_DEXES.find((dex) => dex.id === id) ?? null;
}
function useLaunchSession() {
  const [isLaunched, setIsLaunched] = useState(() => Boolean(readJsonStorage(LAUNCH_STORAGE_KEY, false)));
  const [isDexSelectorOpen, setDexSelectorOpen] = useState(false);
  const [selectedDexId, setSelectedDexId] = useState(() => String(readJsonStorage(DEX_SELECTION_STORAGE_KEY, "") || ""));
  const [isSidebarOpen, setSidebarOpen] = useState(false);
  const [isResultOpen, setResultOpen] = useState(false);
  const [toasts, setToasts] = useState([]);
  const [mintedReports, setMintedReports] = useState(() => readJsonStorage(REPORT_STORAGE_KEY, []));
  const selectedDex = useMemo(() => findDexById(selectedDexId), [selectedDexId]);
  useEffect(() => {
    writeJsonStorage(LAUNCH_STORAGE_KEY, isLaunched);
  }, [isLaunched]);
  useEffect(() => {
    writeJsonStorage(DEX_SELECTION_STORAGE_KEY, selectedDexId);
  }, [selectedDexId]);
  useEffect(() => {
    const onStorage = (event) => {
      if (event.key === LAUNCH_STORAGE_KEY && event.newValue) {
        try {
          setIsLaunched(Boolean(JSON.parse(event.newValue)));
        } catch {
        }
      }
      if (event.key === DEX_SELECTION_STORAGE_KEY && event.newValue) {
        try {
          setSelectedDexId(String(JSON.parse(event.newValue) ?? ""));
        } catch {
        }
      }
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);
  const launch = () => {
    setIsLaunched(true);
    setDexSelectorOpen(true);
  };
  const closeDexSelector = () => setDexSelectorOpen(false);
  const chooseDex = (dexId) => {
    setSelectedDexId(dexId);
    setDexSelectorOpen(false);
    setIsLaunched(true);
    setSidebarOpen(false);
    setResultOpen(false);
  };
  const pushToast = (title, message = "") => {
    const next = createToast(title, message);
    setToasts((prev) => [...prev, next]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((item) => item.id !== next.id));
    }, TOAST_TTL_MS);
  };
  const addMintedReport = (report) => {
    setMintedReports((prev) => {
      const next = [report, ...prev];
      writeJsonStorage(REPORT_STORAGE_KEY, next);
      return next;
    });
  };
  const clearReports = () => {
    setMintedReports([]);
    writeJsonStorage(REPORT_STORAGE_KEY, []);
  };
  const reportCount = useMemo(() => mintedReports.length, [mintedReports.length]);
  return {
    isLaunched,
    isDexSelectorOpen,
    selectedDex,
    isSidebarOpen,
    isResultOpen,
    toasts,
    mintedReports,
    reportCount,
    launch,
    chooseDex,
    closeDexSelector,
    setSidebarOpen,
    setResultOpen,
    pushToast,
    addMintedReport,
    clearReports
  };
}
function useWalletGate() {
  const { address, isConnected, chainId } = useAccount();
  const { connectAsync, connectors, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const [error, setError] = useState("");
  const connectWallet = async () => {
    try {
      setError("");
      const connector = connectors?.[0];
      if (!connector) throw new Error("No wallet connector found");
      await connectAsync({ connector });
      return { ok: true, error: "" };
    } catch (err) {
      const message = err?.message ?? "Wallet connection failed";
      setError(message);
      return { ok: false, error: message };
    }
  };
  const disconnectWallet = () => {
    try {
      disconnect();
      setError("");
      return { ok: true, error: "" };
    } catch (err) {
      const message = err?.message ?? "Wallet disconnect failed";
      setError(message);
      return { ok: false, error: message };
    }
  };
  const gate = useMemo(() => {
    if (!isConnected) {
      return {
        allowed: false,
        reason: "Wallet not connected. Connect wallet before running PreFlight."
      };
    }
    return {
      allowed: true,
      reason: ""
    };
  }, [isConnected]);
  return {
    address,
    chainId,
    isConnected,
    isConnecting,
    error,
    connectWallet,
    disconnectWallet,
    gate
  };
}
function LandingSection({ onLaunch, isLaunched = false }) {
  return /* @__PURE__ */ jsxs(Fragment, { children: [
    /* @__PURE__ */ jsx("div", { className: "fixed inset-0 flex items-center justify-center pointer-events-none z-0", children: /* @__PURE__ */ jsx(
      Shield,
      {
        size: 540,
        strokeWidth: 0.5,
        className: "text-brand-cyan opacity-[0.04] animate-pulse"
      }
    ) }),
    /* @__PURE__ */ jsxs("div", { className: "relative z-10 max-w-6xl mx-auto px-6 py-20", children: [
      /* @__PURE__ */ jsxs("div", { className: "relative text-center space-y-8 mb-40 pt-10", children: [
        /* @__PURE__ */ jsxs("div", { className: "inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-brand-cyan/10 border border-brand-cyan/20 text-brand-cyan text-[11px] font-black uppercase tracking-[0.2em] animate-pulse", children: [
          /* @__PURE__ */ jsx(Activity, { size: 14 }),
          " Arbitrum Security Gateway v1.0 Active"
        ] }),
        /* @__PURE__ */ jsxs("h1", { className: "text-7xl font-black tracking-tighter text-white leading-tight", children: [
          "Pre",
          /* @__PURE__ */ jsx("span", { className: "text-brand-cyan", children: "Flight" })
        ] }),
        /* @__PURE__ */ jsxs("p", { className: "text-xl text-slate-400 max-w-4xl mx-auto leading-relaxed font-medium", children: [
          "PreFlight is a ",
          /* @__PURE__ */ jsx("span", { className: "text-white font-bold", children: "transaction security layer" }),
          " for Arbitrum DeFi. It validates user intent before execution by combining off-chain CRE simulation, deterministic guard checks, and policy-based verdicts in one explainable workflow."
        ] }),
        /* @__PURE__ */ jsx("p", { className: "text-sm text-slate-500 max-w-3xl mx-auto", children: "Launch flow: choose DEX (Camelot or SaucerSwap) -> open secure DEX runtime page -> intercept intent -> run checks -> mint report -> execute." }),
        /* @__PURE__ */ jsxs("div", { className: "flex flex-col items-center gap-6", children: [
          /* @__PURE__ */ jsxs(
            "button",
            {
              onClick: onLaunch,
              className: "btn-primary flex items-center gap-3 px-12 py-5 shadow-[0_0_50px_rgba(0,242,254,0.3)] group relative overflow-hidden",
              children: [
                isLaunched ? "PreFlight Launcher Active" : "Launch Security Layer",
                /* @__PURE__ */ jsx(ArrowRight, { size: 18, className: "group-hover:translate-x-1 transition-transform" })
              ]
            }
          ),
          /* @__PURE__ */ jsxs("div", { className: "flex flex-wrap justify-center gap-6 text-[10px] text-slate-500 font-bold uppercase tracking-[0.2em]", children: [
            /* @__PURE__ */ jsx("span", { children: "• Swap Integrity" }),
            /* @__PURE__ */ jsx("span", { children: "• Vault Protection" }),
            /* @__PURE__ */ jsx("span", { children: "• LP Safeguards" }),
            /* @__PURE__ */ jsx("span", { children: "• Report NFT Proof" })
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "mb-40 grid grid-cols-1 md:grid-cols-2 gap-20 items-center", children: [
        /* @__PURE__ */ jsxs("div", { className: "space-y-6", children: [
          /* @__PURE__ */ jsx("h2", { className: "text-3xl font-black text-white uppercase tracking-tight", children: "Why This Exists" }),
          /* @__PURE__ */ jsx("p", { className: "text-slate-400 leading-relaxed", children: "Wallet previews mostly show top-level calls and outputs. Many failures happen in internal routes, adapter hops, vault accounting, or temporary manipulation windows. PreFlight was designed to expose those blind spots before you submit execution." }),
          /* @__PURE__ */ jsxs("div", { className: "grid grid-cols-2 gap-4 pt-4", children: [
            /* @__PURE__ */ jsxs("div", { className: "p-4 bg-white/5 rounded-xl border border-white/10", children: [
              /* @__PURE__ */ jsx("div", { className: "text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider", children: "Zero-Trust" }),
              /* @__PURE__ */ jsx("p", { className: "text-[10px] text-slate-500", children: "Routers, pools, and vault paths are treated as untrusted by default." })
            ] }),
            /* @__PURE__ */ jsxs("div", { className: "p-4 bg-white/5 rounded-xl border border-white/10", children: [
              /* @__PURE__ */ jsx("div", { className: "text-brand-cyan font-bold mb-1 uppercase text-[10px] tracking-wider", children: "Explainable" }),
              /* @__PURE__ */ jsx("p", { className: "text-[10px] text-slate-500", children: "Each decision includes trace, economics, and policy evidence for users." })
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxs("div", { className: "relative", children: [
          /* @__PURE__ */ jsx("div", { className: "absolute -inset-4 bg-brand-cyan/20 blur-3xl opacity-20 rounded-full" }),
          /* @__PURE__ */ jsxs("div", { className: "relative glass-card p-8 rounded-3xl border border-white/10", children: [
            /* @__PURE__ */ jsx("div", { className: "text-[10px] font-mono text-brand-cyan mb-4 uppercase tracking-[0.2em]", children: "System_Logic::Abstraction" }),
            /* @__PURE__ */ jsxs("div", { className: "space-y-4", children: [
              /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-4 text-xs", children: [
                /* @__PURE__ */ jsx("div", { className: "w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20", children: "1" }),
                /* @__PURE__ */ jsx("div", { className: "text-white", children: "Capture User Intent" })
              ] }),
              /* @__PURE__ */ jsx("div", { className: "h-8 w-px bg-white/10 ml-4" }),
              /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-4 text-xs", children: [
                /* @__PURE__ */ jsx("div", { className: "w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20", children: "2" }),
                /* @__PURE__ */ jsx("div", { className: "text-white font-bold", children: "Run PreFlight Verification" })
              ] }),
              /* @__PURE__ */ jsxs("div", { className: "ml-12 border-l-2 border-brand-cyan/30 pl-4 space-y-2 py-2", children: [
                /* @__PURE__ */ jsx("div", { className: "text-[10px] text-slate-500 font-mono italic", children: "├─ Off-chain simulation (CRE)" }),
                /* @__PURE__ */ jsx("div", { className: "text-[10px] text-slate-500 font-mono italic", children: "├─ On-chain guards (router-level)" }),
                /* @__PURE__ */ jsx("div", { className: "text-[10px] text-slate-500 font-mono italic", children: "└─ Risk policy aggregation" })
              ] }),
              /* @__PURE__ */ jsx("div", { className: "h-8 w-px bg-white/10 ml-4" }),
              /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-4 text-xs", children: [
                /* @__PURE__ */ jsx("div", { className: "w-8 h-8 rounded bg-brand-cyan/10 flex items-center justify-center text-brand-cyan font-bold italic border border-brand-cyan/20", children: "3" }),
                /* @__PURE__ */ jsx("div", { className: "text-white", children: "Mint Report NFT and Execute" })
              ] })
            ] })
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "mb-40", children: [
        /* @__PURE__ */ jsxs("div", { className: "text-center mb-16", children: [
          /* @__PURE__ */ jsx("h2", { className: "text-3xl font-black text-white uppercase tracking-tight", children: "How PreFlight Protects You" }),
          /* @__PURE__ */ jsx("p", { className: "text-slate-500 mt-2", children: "Three-layer integrity model with deterministic and simulated checks." })
        ] }),
        /* @__PURE__ */ jsx("div", { className: "grid grid-cols-1 md:grid-cols-3 gap-8", children: [
          {
            icon: /* @__PURE__ */ jsx(Fingerprint, {}),
            title: "State Integrity",
            who: "On-Chain Guards",
            desc: "Checks pool/vault state invariants and rejects paths outside safe policy bounds."
          },
          {
            icon: /* @__PURE__ */ jsx(Layers, {}),
            title: "Execution Integrity",
            who: "Simulation Engine",
            desc: "Simulates path-level behavior to surface hidden call effects and unsafe route behavior."
          },
          {
            icon: /* @__PURE__ */ jsx(Database, {}),
            title: "Accounting Integrity",
            who: "Post-Check Policy",
            desc: "Validates output consistency, slippage boundaries, and accounting assumptions."
          }
        ].map((card, i) => /* @__PURE__ */ jsxs("div", { className: "group glass-card p-10 rounded-[2.5rem] border border-white/5 hover:border-brand-cyan/40 transition-all duration-500", children: [
          /* @__PURE__ */ jsx("div", { className: "text-brand-cyan mb-6 group-hover:scale-110 transition-transform", children: card.icon }),
          /* @__PURE__ */ jsx("div", { className: "text-[10px] font-black text-brand-cyan uppercase tracking-widest mb-2", children: card.who }),
          /* @__PURE__ */ jsx("div", { className: "text-white font-black mb-4 uppercase text-sm tracking-widest", children: card.title }),
          /* @__PURE__ */ jsx("p", { className: "text-slate-400 text-xs leading-relaxed", children: card.desc })
        ] }, i)) })
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "mb-40 bg-brand-cyan/5 border border-brand-cyan/20 rounded-[3rem] p-10 md:p-16 relative overflow-hidden", children: [
        /* @__PURE__ */ jsx("div", { className: "absolute top-0 right-0 p-8 opacity-10", children: /* @__PURE__ */ jsx(Globe, { size: 120, className: "text-brand-cyan" }) }),
        /* @__PURE__ */ jsxs("div", { className: "max-w-3xl space-y-5", children: [
          /* @__PURE__ */ jsx("h2", { className: "text-3xl font-black text-white uppercase", children: "Trust Through Transparency" }),
          /* @__PURE__ */ jsx("p", { className: "text-slate-400 leading-relaxed", children: "PreFlight is built to reduce risk, not to make impossible guarantees. No security system can guarantee 100% safety under all market and smart-contract conditions. The product is strongest when users can inspect clear evidence, understand risk levels, and decide with context." }),
          /* @__PURE__ */ jsxs("div", { className: "grid gap-3 md:grid-cols-3 text-[11px]", children: [
            /* @__PURE__ */ jsxs("div", { className: "rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300", children: [
              /* @__PURE__ */ jsx("span", { className: "text-brand-cyan font-bold uppercase tracking-widest text-[10px]", children: "Current coverage" }),
              /* @__PURE__ */ jsx("p", { className: "mt-1", children: "Arbitrum-focused swap, liquidity, and vault pre-check workflows." })
            ] }),
            /* @__PURE__ */ jsxs("div", { className: "rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300", children: [
              /* @__PURE__ */ jsx("span", { className: "text-brand-cyan font-bold uppercase tracking-widest text-[10px]", children: "Known limits" }),
              /* @__PURE__ */ jsx("p", { className: "mt-1", children: "Cross-tab intent capture is partial without extension-based content adapters." })
            ] }),
            /* @__PURE__ */ jsxs("div", { className: "rounded-xl border border-white/10 bg-black/25 p-3 text-slate-300", children: [
              /* @__PURE__ */ jsx("span", { className: "text-brand-cyan font-bold uppercase tracking-widest text-[10px]", children: "Roadmap" }),
              /* @__PURE__ */ jsx("p", { className: "mt-1", children: "Arbitrum first, then protocol adapters for Uni, Sushi, and multi-chain expansion." })
            ] })
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "mb-40", children: [
        /* @__PURE__ */ jsx("h2", { className: "text-3xl font-black text-white uppercase tracking-tight mb-10 text-center", children: "User Safety Flow" }),
        /* @__PURE__ */ jsx("div", { className: "grid gap-6 md:grid-cols-4", children: [
          { icon: /* @__PURE__ */ jsx(ShieldCheck, { size: 14 }), label: "Wallet gate", text: "Check starts only after wallet is connected." },
          { icon: /* @__PURE__ */ jsx(Clock3, { size: 14 }), label: "Freshness guard", text: "Report is revalidated if preview becomes stale (>20s)." },
          { icon: /* @__PURE__ */ jsx(Database, { size: 14 }), label: "Mint proof", text: "Risk report can be minted to preserve evidence." },
          { icon: /* @__PURE__ */ jsx(AlertTriangle, { size: 14 }), label: "Execute guard", text: "Execution remains behind risk-aware route controls." }
        ].map((item, i) => /* @__PURE__ */ jsxs("div", { className: "bg-white/[0.02] border border-white/5 p-6 rounded-3xl hover:bg-white/[0.04] transition-colors", children: [
          /* @__PURE__ */ jsx("div", { className: "inline-flex items-center justify-center w-8 h-8 rounded-lg bg-brand-cyan/10 border border-brand-cyan/25 text-brand-cyan mb-3", children: item.icon }),
          /* @__PURE__ */ jsx("h3", { className: "text-white font-black uppercase text-[11px] tracking-widest mb-2", children: item.label }),
          /* @__PURE__ */ jsx("p", { className: "text-[11px] text-slate-500 leading-relaxed", children: item.text })
        ] }, i)) })
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "relative overflow-hidden rounded-[3rem] p-16 text-center bg-gradient-to-b from-brand-cyan/20 to-transparent border border-brand-cyan/10", children: [
        /* @__PURE__ */ jsx("div", { className: "absolute top-0 left-0 w-full h-full bg-[url('https://grainy-gradients.vercel.app/noise.svg')] opacity-20 pointer-events-none" }),
        /* @__PURE__ */ jsx("h2", { className: "text-4xl font-black text-white mb-6 uppercase tracking-tight", children: "Security Is A Process, Not A Checkbox" }),
        /* @__PURE__ */ jsx("p", { className: "text-slate-400 max-w-2xl mx-auto mb-10 leading-relaxed text-sm", children: "Launch PreFlight before every sensitive DeFi action. Review risk evidence, mint audit-ready reports, and execute with stronger confidence than raw wallet previews alone." }),
        /* @__PURE__ */ jsx(
          "button",
          {
            onClick: onLaunch,
            className: "btn-primary px-16 py-5 shadow-2xl relative z-10",
            children: isLaunched ? "Launcher Already Active" : "Activate PreFlight Guard"
          }
        )
      ] })
    ] })
  ] });
}
function DexSelectorModal({ isOpen, onClose, onChoose }) {
  return /* @__PURE__ */ jsx(AnimatePresence, { children: isOpen ? /* @__PURE__ */ jsxs(Fragment, { children: [
    /* @__PURE__ */ jsx(
      motion.div,
      {
        className: "fixed inset-0 z-[180] bg-black/70 backdrop-blur-sm",
        initial: { opacity: 0 },
        animate: { opacity: 1 },
        exit: { opacity: 0 },
        onClick: onClose
      }
    ),
    /* @__PURE__ */ jsxs(
      motion.div,
      {
        className: "fixed left-1/2 top-1/2 z-[190] w-[min(680px,calc(100vw-24px))] -translate-x-1/2 -translate-y-1/2 rounded-3xl glass-card border border-brand-cyan/20 p-5 md:p-7",
        initial: { opacity: 0, scale: 0.96, y: 18 },
        animate: { opacity: 1, scale: 1, y: 0 },
        exit: { opacity: 0, scale: 0.97, y: 12 },
        children: [
          /* @__PURE__ */ jsxs("div", { className: "flex items-start justify-between gap-3 border-b border-white/10 pb-4", children: [
            /* @__PURE__ */ jsxs("div", { children: [
              /* @__PURE__ */ jsx("p", { className: "text-[10px] font-black uppercase tracking-[0.24em] text-brand-cyan", children: "Launch Runtime" }),
              /* @__PURE__ */ jsx("h3", { className: "mt-1 text-2xl font-black uppercase tracking-[0.1em] text-white", children: "Choose Your DEX" }),
              /* @__PURE__ */ jsx("p", { className: "mt-2 text-sm text-slate-400", children: "Select a supported DEX. A dedicated DEX page will open inside PreFlight." })
            ] }),
            /* @__PURE__ */ jsx(
              "button",
              {
                className: "rounded-lg border border-white/10 p-2 text-slate-400 hover:border-white/30 hover:text-white",
                onClick: onClose,
                children: /* @__PURE__ */ jsx(X, { size: 16 })
              }
            )
          ] }),
          /* @__PURE__ */ jsx("div", { className: "mt-5 grid gap-3 md:grid-cols-2", children: SUPPORTED_DEXES.map((dex) => /* @__PURE__ */ jsxs(
            "button",
            {
              onClick: () => onChoose(dex.id),
              className: "text-left rounded-2xl border border-white/10 bg-white/[0.03] p-4 transition hover:border-brand-cyan/40 hover:bg-white/[0.05]",
              children: [
                /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between gap-2", children: [
                  /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
                    /* @__PURE__ */ jsx("div", { className: "h-9 w-9 rounded-lg border border-brand-cyan/30 bg-brand-cyan/10 grid place-items-center text-brand-cyan", children: /* @__PURE__ */ jsx(Layers2, { size: 16 }) }),
                    /* @__PURE__ */ jsxs("div", { children: [
                      /* @__PURE__ */ jsx("div", { className: "text-sm font-black uppercase tracking-[0.12em] text-white", children: dex.name }),
                      /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.14em] text-brand-cyan", children: dex.tag })
                    ] })
                  ] }),
                  /* @__PURE__ */ jsx(Globe, { size: 16, className: "text-slate-500" })
                ] }),
                /* @__PURE__ */ jsx("div", { className: "mt-3 rounded-lg border border-white/10 bg-black/30 p-2 text-[11px] text-slate-400 break-all", children: dex.url })
              ]
            },
            dex.id
          )) })
        ]
      }
    )
  ] }) : null });
}
function LaunchpadPage({ launchSession, onDexSelected }) {
  const {
    isLaunched,
    isDexSelectorOpen,
    launch,
    chooseDex,
    closeDexSelector,
    selectedDex,
    pushToast
  } = launchSession;
  return /* @__PURE__ */ jsxs("div", { className: "relative min-h-[72vh]", children: [
    /* @__PURE__ */ jsx(
      LandingSection,
      {
        isLaunched,
        onLaunch: () => {
          launch();
          pushToast("Launcher activated", "Choose a DEX to open secure runtime page");
        }
      }
    ),
    /* @__PURE__ */ jsx(
      DexSelectorModal,
      {
        isOpen: isDexSelectorOpen,
        onClose: closeDexSelector,
        onChoose: (dexId) => {
          chooseDex(dexId);
          onDexSelected?.();
          pushToast("DEX selected", "DEX runtime page is ready");
        }
      }
    ),
    selectedDex ? /* @__PURE__ */ jsxs("div", { className: "fixed bottom-4 left-4 z-[100] rounded-lg border border-brand-cyan/30 bg-black/70 px-3 py-2 text-[11px] uppercase tracking-[0.14em] text-brand-cyan", children: [
      "Active runtime: ",
      selectedDex.name,
      " (",
      selectedDex.chain,
      ")"
    ] }) : null
  ] });
}
function FloatingLauncher({ hidden = false, disabled = false, onClick }) {
  if (hidden) return null;
  return /* @__PURE__ */ jsxs(
    motion.button,
    {
      type: "button",
      initial: { opacity: 0, scale: 0.85, y: 12 },
      animate: { opacity: 1, scale: 1, y: 0 },
      whileHover: disabled ? {} : { scale: 1.03 },
      whileTap: disabled ? {} : { scale: 0.98 },
      onClick,
      disabled,
      className: "fixed bottom-7 right-7 z-[140] inline-flex items-center gap-2 rounded-full border border-brand-cyan/30 bg-black/70 px-5 py-3 text-sm font-black uppercase tracking-[0.17em] text-brand-cyan shadow-[0_0_30px_rgba(0,242,254,0.22)] backdrop-blur disabled:cursor-not-allowed disabled:opacity-60",
      children: [
        /* @__PURE__ */ jsxs("span", { className: "relative inline-flex h-8 w-8 items-center justify-center rounded-full bg-brand-cyan text-black", children: [
          /* @__PURE__ */ jsx(Shield, { size: 16, fill: "currentColor" }),
          /* @__PURE__ */ jsx("span", { className: "absolute -bottom-1 -right-1 rounded-full bg-black px-1 text-[8px] text-brand-cyan", children: "v1" })
        ] }),
        "PreFlight",
        /* @__PURE__ */ jsx(PanelRightOpen, { size: 14 }),
        /* @__PURE__ */ jsx("span", { className: "pointer-events-none absolute inset-0 -z-10 rounded-full bg-brand-cyan/10 blur-xl" })
      ]
    }
  );
}
function getStatusIcon(status) {
  if (status === "running") return /* @__PURE__ */ jsx(LoaderCircle, { className: "h-4 w-4 animate-spin text-brand-cyan" });
  if (status === "done") return /* @__PURE__ */ jsx(CheckCircle2, { className: "h-4 w-4 text-green-400" });
  if (status === "error") return /* @__PURE__ */ jsx(CircleX, { className: "h-4 w-4 text-red-400" });
  return /* @__PURE__ */ jsx(CircleDashed, { className: "h-4 w-4 text-slate-500" });
}
function statusClass(status) {
  if (status === "running") return "border-brand-cyan/25 bg-brand-cyan/10 text-brand-cyan";
  if (status === "done") return "border-green-500/25 bg-green-500/10 text-green-400";
  if (status === "error") return "border-red-500/25 bg-red-500/10 text-red-400";
  return "border-white/15 bg-white/5 text-slate-400";
}
function CheckTimeline({ timeline }) {
  return /* @__PURE__ */ jsx("ol", { className: "space-y-2.5", children: timeline.map((step, index) => /* @__PURE__ */ jsxs("li", { className: "rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2.5", children: [
    /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between gap-3", children: [
      /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
        getStatusIcon(step.status),
        /* @__PURE__ */ jsx("span", { className: "text-xs font-bold text-white", children: step.label })
      ] }),
      /* @__PURE__ */ jsx("span", { className: `rounded-md border px-2 py-0.5 text-[9px] font-black uppercase tracking-[0.14em] ${statusClass(step.status)}`, children: step.status })
    ] }),
    step.message ? /* @__PURE__ */ jsx("p", { className: "mt-1.5 text-[11px] leading-relaxed text-slate-400", children: step.message }) : null,
    index < timeline.length - 1 ? /* @__PURE__ */ jsx("div", { className: "mt-2 h-px bg-white/5" }) : null
  ] }, step.id)) });
}
function ExecuteTransactionButton({ onClick, disabled, status = "idle" }) {
  const label = status === "pending" ? "Executing..." : "Execute Transaction";
  return /* @__PURE__ */ jsx(
    "button",
    {
      type: "button",
      onClick,
      disabled,
      className: "inline-flex w-full items-center justify-center rounded-xl bg-green-600 px-4 py-3 text-[11px] font-black uppercase tracking-wider text-white transition-all hover:bg-green-500 disabled:cursor-not-allowed disabled:opacity-55",
      children: label
    }
  );
}
function Button({
  children,
  variant = "primary",
  className = "",
  disabled = false,
  ...props
}) {
  const base = "inline-flex items-center justify-center disabled:cursor-not-allowed disabled:opacity-60";
  const variants = {
    primary: "btn-primary px-4 py-2 text-[11px]",
    ghost: "btn-outline px-4 py-2 text-[11px]",
    danger: "bg-red-600 text-white hover:bg-red-500",
    success: "bg-green-600 text-white hover:bg-green-500"
  };
  return /* @__PURE__ */ jsx(
    "button",
    {
      className: `${base} ${variants[variant] ?? variants.primary} ${className}`,
      disabled,
      ...props,
      children
    }
  );
}
function Badge({ label, tone = "neutral", className = "" }) {
  const tones = {
    neutral: "bg-white/10 text-slate-300 border border-white/15",
    info: "bg-brand-cyan/10 text-brand-cyan border border-brand-cyan/30",
    success: "bg-green-500/10 text-green-400 border border-green-500/30",
    warning: "bg-yellow-500/10 text-yellow-300 border border-yellow-500/30",
    critical: "bg-red-500/10 text-red-400 border border-red-500/30"
  };
  return /* @__PURE__ */ jsx(
    "span",
    {
      className: `inline-flex items-center rounded-md px-2 py-1 text-[10px] font-black uppercase tracking-wider ${tones[tone] ?? tones.neutral} ${className}`,
      children: label
    }
  );
}
function Card({ children, className = "" }) {
  return /* @__PURE__ */ jsx("div", { className: `glass-card rounded-2xl p-4 ${className}`, children });
}
function riskTone$1(level) {
  if (level === "CRITICAL") return "critical";
  if (level === "WARNING") return "warning";
  return "success";
}
function SessionSidebar({
  isOpen,
  onClose,
  intent,
  onIntentPatch,
  walletGate,
  sessionPhase,
  checkStatus,
  checkError,
  timeline,
  canRunChecks,
  onRunChecks,
  onViewReport,
  hasReport,
  onReset,
  mintState,
  mintedReport,
  executionState,
  onExecute
}) {
  const walletBadge = useMemo(() => {
    if (!walletGate.isConnected) return { tone: "critical", label: "Wallet disconnected" };
    if (!intent.walletConnectedOnTarget) return { tone: "warning", label: "Target wallet flag off" };
    return { tone: "success", label: "Wallet gate passed" };
  }, [walletGate.isConnected, intent.walletConnectedOnTarget]);
  return /* @__PURE__ */ jsx(AnimatePresence, { children: isOpen ? /* @__PURE__ */ jsxs(Fragment, { children: [
    /* @__PURE__ */ jsx(
      motion.div,
      {
        className: "fixed inset-0 z-[110] bg-black/60 backdrop-blur-sm",
        initial: { opacity: 0 },
        animate: { opacity: 1 },
        exit: { opacity: 0 },
        onClick: onClose
      }
    ),
    /* @__PURE__ */ jsxs(
      motion.aside,
      {
        className: "fixed top-0 right-0 z-[120] w-full h-full glass-card max-w-[430px] flex flex-col shadow-2xl border-l border-brand-cyan/20",
        initial: { x: "100%" },
        animate: { x: 0 },
        exit: { x: "100%" },
        transition: { type: "spring", damping: 25, stiffness: 200 },
        children: [
          /* @__PURE__ */ jsxs("div", { className: "p-5 border-b border-white/5 flex items-center justify-between", children: [
            /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
              /* @__PURE__ */ jsx("div", { className: "w-8 h-8 rounded-lg bg-brand-cyan/10 flex items-center justify-center border border-brand-cyan/30", children: /* @__PURE__ */ jsx(ShieldCheck, { size: 18, className: "text-brand-cyan" }) }),
              /* @__PURE__ */ jsxs("div", { children: [
                /* @__PURE__ */ jsx("h2", { className: "text-base font-black tracking-tight uppercase text-white", children: "PreFlight Session" }),
                /* @__PURE__ */ jsx("p", { className: "text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan/80", children: "Runtime Controls" })
              ] })
            ] }),
            /* @__PURE__ */ jsx("button", { onClick: onClose, className: "p-2 hover:bg-white/5 rounded-full text-gray-500 hover:text-white transition-all", children: /* @__PURE__ */ jsx(X, { size: 20 }) })
          ] }),
          /* @__PURE__ */ jsxs("div", { className: "flex-1 overflow-y-auto p-5 space-y-4", children: [
            /* @__PURE__ */ jsxs(Card, { children: [
              /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between gap-3", children: [
                /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-sm font-bold text-white", children: [
                  /* @__PURE__ */ jsx(Wallet, { size: 16 }),
                  " Wallet Gate"
                ] }),
                /* @__PURE__ */ jsx(Badge, { label: walletBadge.label, tone: walletBadge.tone })
              ] }),
              /* @__PURE__ */ jsxs("div", { className: "mt-3 flex flex-wrap gap-2", children: [
                /* @__PURE__ */ jsx(
                  Button,
                  {
                    variant: walletGate.isConnected ? "ghost" : "primary",
                    className: "min-w-[150px]",
                    onClick: walletGate.isConnected ? walletGate.disconnectWallet : walletGate.connectWallet,
                    children: walletGate.isConnected ? "Disconnect Wallet" : "Connect Wallet"
                  }
                ),
                /* @__PURE__ */ jsxs("label", { className: "inline-flex items-center gap-2 rounded-lg border border-white/15 bg-black/35 px-3 py-2 text-[11px] text-slate-300", children: [
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      type: "checkbox",
                      checked: Boolean(intent.walletConnectedOnTarget),
                      onChange: (event) => onIntentPatch({ walletConnectedOnTarget: event.target.checked })
                    }
                  ),
                  "Wallet connected on target"
                ] })
              ] }),
              walletGate.error ? /* @__PURE__ */ jsx("p", { className: "mt-2 text-[11px] text-red-400", children: walletGate.error }) : null
            ] }),
            /* @__PURE__ */ jsxs(Card, { children: [
              /* @__PURE__ */ jsxs("div", { className: "mb-2 flex items-center justify-between", children: [
                /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-sm font-bold text-white", children: [
                  /* @__PURE__ */ jsx(Link2, { size: 16 }),
                  " Intent Source"
                ] }),
                /* @__PURE__ */ jsx(Badge, { label: intent.type, tone: "info" })
              ] }),
              /* @__PURE__ */ jsxs("div", { className: "grid grid-cols-2 gap-2 text-xs", children: [
                /* @__PURE__ */ jsxs("label", { className: "space-y-1 col-span-2", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Target URL" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70",
                      value: intent.targetUrl ?? "",
                      onChange: (event) => onIntentPatch({ targetUrl: event.target.value }),
                      placeholder: "https://app.camelot.exchange"
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1 col-span-2", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Sender (from)" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono",
                      value: intent.from ?? "",
                      onChange: (event) => onIntentPatch({ from: event.target.value }),
                      placeholder: "0x..."
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Protocol" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70",
                      value: intent.protocol,
                      onChange: (event) => onIntentPatch({ protocol: event.target.value })
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Operation" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70",
                      value: intent.opType,
                      onChange: (event) => onIntentPatch({ opType: event.target.value })
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Pair / Vault" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70",
                      value: intent.payload?.pair ?? "",
                      onChange: (event) => onIntentPatch({ payload: { pair: event.target.value } })
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Amount" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70",
                      value: intent.payload?.amount ?? "",
                      onChange: (event) => onIntentPatch({ payload: { amount: event.target.value } })
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Router Address" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono",
                      value: intent.payload?.routerAddress ?? "",
                      onChange: (event) => onIntentPatch({ payload: { routerAddress: event.target.value } }),
                      placeholder: "0x..."
                    }
                  )
                ] }),
                /* @__PURE__ */ jsxs("label", { className: "space-y-1", children: [
                  /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Vault Address" }),
                  /* @__PURE__ */ jsx(
                    "input",
                    {
                      className: "w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono",
                      value: intent.payload?.vaultAddress ?? "",
                      onChange: (event) => onIntentPatch({ payload: { vaultAddress: event.target.value } }),
                      placeholder: "0x..."
                    }
                  )
                ] })
              ] }),
              /* @__PURE__ */ jsxs("label", { className: "mt-2 block space-y-1 text-xs", children: [
                /* @__PURE__ */ jsx("span", { className: "text-[10px] uppercase tracking-[0.15em] text-slate-500", children: "Transaction Calldata (hex)" }),
                /* @__PURE__ */ jsx(
                  "textarea",
                  {
                    className: "min-h-[76px] w-full rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-brand-cyan/70 font-mono",
                    value: intent.payload?.data ?? "",
                    onChange: (event) => onIntentPatch({ payload: { data: event.target.value } }),
                    placeholder: "0x..."
                  }
                )
              ] }),
              /* @__PURE__ */ jsx("p", { className: "mt-2 text-[10px] text-slate-500 leading-relaxed", children: "For real CRE off-chain checks, set `from`, router/vault, and calldata fields so payload matches the simulation trigger format." })
            ] }),
            /* @__PURE__ */ jsxs(Card, { children: [
              /* @__PURE__ */ jsxs("div", { className: "mb-3 flex items-center justify-between", children: [
                /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-sm font-bold text-white", children: [
                  /* @__PURE__ */ jsx(FileSearch2, { size: 16 }),
                  " Check Timeline"
                ] }),
                /* @__PURE__ */ jsx(Badge, { label: sessionPhase.replaceAll("_", " "), tone: "neutral" })
              ] }),
              checkError ? /* @__PURE__ */ jsx("p", { className: "mb-2 rounded-lg border border-red-500/20 bg-red-500/10 px-2 py-1 text-xs text-red-300", children: checkError }) : null,
              /* @__PURE__ */ jsx(CheckTimeline, { timeline }),
              /* @__PURE__ */ jsxs("div", { className: "pt-3 mt-3 border-t border-white/5 space-y-2", children: [
                /* @__PURE__ */ jsxs(
                  "button",
                  {
                    onClick: onRunChecks,
                    disabled: !canRunChecks || checkStatus === "running",
                    className: "w-full py-3 bg-brand-cyan hover:brightness-110 text-black font-black rounded-xl transition-all neon-glow flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed",
                    children: [
                      /* @__PURE__ */ jsx(Zap, { size: 16, fill: "black" }),
                      " ",
                      checkStatus === "running" ? "RUNNING CHECK PREFLIGHT..." : "CHECK PREFLIGHT"
                    ]
                  }
                ),
                /* @__PURE__ */ jsxs("div", { className: "flex gap-2", children: [
                  /* @__PURE__ */ jsx(Button, { variant: "ghost", className: "flex-1", onClick: onViewReport, disabled: !hasReport, children: "View Report" }),
                  /* @__PURE__ */ jsxs(Button, { variant: "ghost", className: "flex-1", onClick: onReset, children: [
                    /* @__PURE__ */ jsx(RefreshCcw, { size: 14, className: "mr-1" }),
                    " Reset"
                  ] })
                ] })
              ] })
            ] }),
            /* @__PURE__ */ jsxs(Card, { children: [
              /* @__PURE__ */ jsxs("div", { className: "mb-3 flex items-center justify-between", children: [
                /* @__PURE__ */ jsx("p", { className: "text-sm font-bold text-white", children: "Post-check Actions" }),
                mintedReport ? /* @__PURE__ */ jsx(Badge, { label: mintedReport.riskLevel, tone: riskTone$1(mintedReport.riskLevel) }) : /* @__PURE__ */ jsx(Badge, { label: "Not minted", tone: "warning" })
              ] }),
              mintState.status === "pending" ? /* @__PURE__ */ jsx("p", { className: "text-xs text-brand-cyan", children: "Minting report NFT..." }) : null,
              mintState.status === "error" ? /* @__PURE__ */ jsx("p", { className: "text-xs text-red-400", children: mintState.error }) : null,
              mintedReport ? /* @__PURE__ */ jsxs("div", { className: "space-y-2 text-xs rounded-lg bg-white/[0.02] border border-white/10 p-3", children: [
                /* @__PURE__ */ jsxs("p", { className: "text-slate-300", children: [
                  "Token ID: #",
                  mintedReport.tokenId
                ] }),
                /* @__PURE__ */ jsx("p", { className: "font-mono text-slate-500 text-[11px] break-all", children: mintedReport.txHash })
              ] }) : /* @__PURE__ */ jsx("p", { className: "text-xs text-slate-400", children: "Mint report in modal to unlock guarded execution." }),
              /* @__PURE__ */ jsx("div", { className: "mt-3", children: /* @__PURE__ */ jsx(ExecuteTransactionButton, { onClick: onExecute, disabled: !mintedReport || executionState.status === "pending", status: executionState.status }) }),
              executionState.status === "success" ? /* @__PURE__ */ jsx("p", { className: "mt-2 rounded-lg border border-green-500/25 bg-green-500/10 px-2 py-1 text-xs text-green-300", children: "Transaction executed successfully." }) : null,
              executionState.status === "error" ? /* @__PURE__ */ jsx("p", { className: "mt-2 rounded-lg border border-red-500/25 bg-red-500/10 px-2 py-1 text-xs text-red-300", children: executionState.error }) : null
            ] })
          ] }),
          /* @__PURE__ */ jsxs("div", { className: "p-4 bg-black/40 border-t border-white/5 flex items-center justify-center gap-2", children: [
            /* @__PURE__ */ jsx("div", { className: "w-1.5 h-1.5 rounded-full bg-green-500 shadow-[0_0_5px_#22c55e]" }),
            /* @__PURE__ */ jsx("span", { className: "text-[9px] font-bold text-gray-500 uppercase tracking-[0.3em]", children: "Arbitrum One Mainnet Active" })
          ] })
        ]
      }
    )
  ] }) : null });
}
function getScoreColor(score, riskLevel) {
  if (riskLevel === "CRITICAL" || score <= 50) return "#ef4444";
  if (riskLevel === "WARNING" || score <= 80) return "#fbbf24";
  return "#00F2FE";
}
function RiskShield({ score = 0, riskLevel = "SAFE" }) {
  const safeScore = Math.max(0, Math.min(100, Number(score) || 0));
  const radius = 45;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - safeScore / 100 * circumference;
  const color = getScoreColor(safeScore, riskLevel);
  return /* @__PURE__ */ jsxs("div", { className: "relative flex flex-col items-center justify-center p-6 bg-white/[0.03] rounded-3xl border border-white/5", children: [
    /* @__PURE__ */ jsxs("div", { className: "relative w-40 h-40", children: [
      /* @__PURE__ */ jsxs("svg", { className: "w-full h-full transform -rotate-90", children: [
        /* @__PURE__ */ jsx("circle", { cx: "80", cy: "80", r: radius, stroke: "currentColor", strokeWidth: "8", fill: "transparent", className: "text-white/5" }),
        /* @__PURE__ */ jsx(
          motion.circle,
          {
            cx: "80",
            cy: "80",
            r: radius,
            stroke: color,
            strokeWidth: "8",
            fill: "transparent",
            strokeDasharray: circumference,
            initial: { strokeDashoffset: circumference },
            animate: { strokeDashoffset: offset },
            transition: { duration: 1.2, ease: "easeOut" },
            strokeLinecap: "round"
          }
        )
      ] }),
      /* @__PURE__ */ jsxs("div", { className: "absolute inset-0 flex flex-col items-center justify-center", children: [
        /* @__PURE__ */ jsx("span", { className: "text-4xl font-black text-white", children: safeScore }),
        /* @__PURE__ */ jsx("span", { className: "text-[10px] font-bold text-gray-500 uppercase tracking-widest", children: "Integrity" })
      ] })
    ] }),
    /* @__PURE__ */ jsxs("div", { className: "mt-4 w-full px-4", children: [
      /* @__PURE__ */ jsxs("div", { className: "flex justify-between text-[10px] font-bold uppercase tracking-tighter mb-1", children: [
        /* @__PURE__ */ jsx("span", { className: "text-gray-500", children: "Risk Level" }),
        /* @__PURE__ */ jsx("span", { style: { color }, children: riskLevel })
      ] }),
      /* @__PURE__ */ jsx("div", { className: "h-1 w-full bg-white/5 rounded-full overflow-hidden", children: /* @__PURE__ */ jsx(
        motion.div,
        {
          initial: { width: 0 },
          animate: { width: `${safeScore}%` },
          className: "h-full",
          style: { backgroundColor: color }
        }
      ) })
    ] })
  ] });
}
function normalizeEntries(data) {
  if (!data || typeof data !== "object") return [];
  return Object.entries(data).map(([key, value]) => {
    const formatted = typeof value === "boolean" ? value ? "true" : "false" : typeof value === "number" ? String(value) : String(value ?? "n/a");
    const tone = typeof value === "boolean" && value ? "warn" : "ok";
    return { key, formatted, tone };
  });
}
function FlagRow({ label, value, tone = "ok" }) {
  const toneClass = tone === "warn" ? "bg-yellow-500/10 text-yellow-300 border-yellow-500/20" : "bg-green-500/10 text-green-400 border-green-500/20";
  return /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between p-3 rounded-lg bg-white/[0.02] border border-white/5", children: [
    /* @__PURE__ */ jsxs("div", { className: "flex flex-col", children: [
      /* @__PURE__ */ jsx("span", { className: "text-xs font-bold text-white uppercase tracking-wide", children: label }),
      /* @__PURE__ */ jsx("span", { className: "text-[10px] text-gray-500", children: value })
    ] }),
    /* @__PURE__ */ jsx("span", { className: `text-[10px] px-2 py-1 rounded font-bold border uppercase ${toneClass}`, children: tone === "warn" ? "Warn" : "Pass" })
  ] });
}
function RiskBreakdown({ report }) {
  const traceEntries = normalizeEntries(report?.offchain?.trace);
  const economicEntries = normalizeEntries(report?.offchain?.economic);
  const onchainChecks = report?.onchain?.checks ?? [];
  return /* @__PURE__ */ jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxs("div", { children: [
      /* @__PURE__ */ jsx("h4", { className: "text-[10px] font-black uppercase tracking-widest text-gray-500 mb-3", children: "Trace & Economic Flags" }),
      /* @__PURE__ */ jsx("div", { className: "grid gap-2 md:grid-cols-2", children: [...traceEntries.slice(0, 4), ...economicEntries.slice(0, 4)].map((item) => /* @__PURE__ */ jsx(FlagRow, { label: item.key, value: item.formatted, tone: item.tone }, `${item.key}_${item.formatted}`)) })
    ] }),
    /* @__PURE__ */ jsxs("div", { children: [
      /* @__PURE__ */ jsx("h4", { className: "text-[10px] font-black uppercase tracking-widest text-gray-500 mb-3", children: "On-chain Check Status" }),
      /* @__PURE__ */ jsx("div", { className: "grid gap-2 md:grid-cols-2", children: onchainChecks.length ? onchainChecks.map((check) => /* @__PURE__ */ jsxs("div", { className: "rounded-lg bg-white/[0.02] border border-white/5 p-3", children: [
        /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2 text-[10px] text-brand-cyan uppercase tracking-wide mb-1", children: [
          /* @__PURE__ */ jsx(ShieldCheck, { size: 12 }),
          " ",
          check.id
        ] }),
        /* @__PURE__ */ jsx("div", { className: "text-xs text-white font-bold", children: check.label }),
        /* @__PURE__ */ jsx("div", { className: "text-[10px] text-yellow-300 uppercase tracking-wide mt-1", children: check.status })
      ] }, check.id)) : /* @__PURE__ */ jsx("p", { className: "text-xs text-slate-500", children: "No on-chain checks returned." }) })
    ] })
  ] });
}
function MintReportButton({ onClick, status = "idle" }) {
  const label = status === "pending" ? "Minting Report..." : "Mint On-Chain Report";
  return /* @__PURE__ */ jsxs(
    "button",
    {
      type: "button",
      onClick,
      disabled: status === "pending",
      className: "inline-flex items-center justify-center gap-2 rounded-xl bg-brand-cyan px-4 py-2 text-[11px] font-black uppercase tracking-wider text-black transition-all hover:brightness-110 hover:shadow-[0_0_28px_rgba(0,242,254,0.35)] disabled:cursor-not-allowed disabled:opacity-70",
      children: [
        /* @__PURE__ */ jsx(FileText, { size: 14 }),
        label
      ]
    }
  );
}
function toneFromRisk(level) {
  if (level === "CRITICAL") return "critical";
  if (level === "WARNING") return "warning";
  return "success";
}
function ResultModal({ isOpen, onClose, report, secondsLeft, mintState, onMint, onRecheck }) {
  const riskLevel = report?.final?.riskLevel ?? "SAFE";
  return /* @__PURE__ */ jsx(AnimatePresence, { children: isOpen ? /* @__PURE__ */ jsxs(Fragment, { children: [
    /* @__PURE__ */ jsx(
      motion.div,
      {
        className: "fixed inset-0 z-[165] bg-black/70 backdrop-blur-sm",
        initial: { opacity: 0 },
        animate: { opacity: 1 },
        exit: { opacity: 0 },
        onClick: onClose
      }
    ),
    /* @__PURE__ */ jsxs(
      motion.div,
      {
        className: "fixed left-1/2 top-1/2 z-[170] w-[min(980px,calc(100vw-18px))] -translate-x-1/2 -translate-y-1/2 glass-card rounded-3xl border border-brand-cyan/20 p-4 shadow-[0_0_60px_rgba(0,0,0,0.65)] md:p-6",
        initial: { opacity: 0, y: 24, scale: 0.98 },
        animate: { opacity: 1, y: 0, scale: 1 },
        exit: { opacity: 0, y: 16, scale: 0.98 },
        children: [
          /* @__PURE__ */ jsxs("div", { className: "mb-4 flex items-start justify-between gap-3 border-b border-white/10 pb-3", children: [
            /* @__PURE__ */ jsxs("div", { children: [
              /* @__PURE__ */ jsx("p", { className: "text-[10px] font-black uppercase tracking-[0.22em] text-brand-cyan", children: "PreFlight Report" }),
              /* @__PURE__ */ jsx("h3", { className: "text-xl font-black uppercase tracking-[0.09em] text-white", children: "Off-chain + On-chain Summary" })
            ] }),
            /* @__PURE__ */ jsx(
              "button",
              {
                type: "button",
                onClick: onClose,
                className: "rounded-lg border border-white/10 p-2 text-slate-400 transition hover:border-white/30 hover:text-white",
                children: /* @__PURE__ */ jsx(X, { size: 16 })
              }
            )
          ] }),
          !report ? /* @__PURE__ */ jsx("div", { className: "rounded-xl border border-white/10 bg-white/[0.03] p-6 text-sm text-slate-400", children: "Run checks first to generate a report." }) : /* @__PURE__ */ jsxs("div", { className: "space-y-5", children: [
            /* @__PURE__ */ jsxs("div", { className: "grid gap-4 md:grid-cols-[280px_1fr]", children: [
              /* @__PURE__ */ jsx(RiskShield, { score: report.final.riskScore, riskLevel: report.final.riskLevel }),
              /* @__PURE__ */ jsxs("div", { className: "space-y-3 rounded-2xl border border-white/10 bg-white/[0.02] p-4", children: [
                /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between", children: [
                  /* @__PURE__ */ jsx("div", { className: "text-[10px] font-black uppercase tracking-[0.15em] text-slate-400", children: "Final Verdict" }),
                  /* @__PURE__ */ jsx(Badge, { label: riskLevel, tone: toneFromRisk(riskLevel) })
                ] }),
                /* @__PURE__ */ jsx("p", { className: "text-sm text-slate-200 leading-relaxed", children: report.final.verdictText }),
                /* @__PURE__ */ jsxs("div", { className: "grid grid-cols-2 gap-2 text-xs text-slate-300 md:grid-cols-4", children: [
                  /* @__PURE__ */ jsxs("div", { className: "rounded-lg border border-white/10 bg-black/25 p-2", children: [
                    /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.14em] text-slate-500", children: "Type" }),
                    /* @__PURE__ */ jsx("div", { className: "mt-1 font-semibold text-white", children: report.intent.type })
                  ] }),
                  /* @__PURE__ */ jsxs("div", { className: "rounded-lg border border-white/10 bg-black/25 p-2", children: [
                    /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.14em] text-slate-500", children: "Operation" }),
                    /* @__PURE__ */ jsx("div", { className: "mt-1 font-semibold text-white", children: report.offchain.operation })
                  ] }),
                  /* @__PURE__ */ jsxs("div", { className: "rounded-lg border border-white/10 bg-black/25 p-2", children: [
                    /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.14em] text-slate-500", children: "Protocol" }),
                    /* @__PURE__ */ jsx("div", { className: "mt-1 font-semibold text-white", children: report.intent.protocol })
                  ] }),
                  /* @__PURE__ */ jsxs("div", { className: "rounded-lg border border-white/10 bg-black/25 p-2", children: [
                    /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.14em] text-slate-500", children: "Network" }),
                    /* @__PURE__ */ jsx("div", { className: "mt-1 font-semibold text-white", children: report.offchain.network })
                  ] })
                ] }),
                /* @__PURE__ */ jsxs("div", { className: "flex flex-wrap items-center gap-2 rounded-lg border border-yellow-500/30 bg-yellow-500/10 px-3 py-2 text-xs text-yellow-200", children: [
                  /* @__PURE__ */ jsx(Clock3, { size: 14 }),
                  "Mint window freshness: ",
                  secondsLeft,
                  "s",
                  secondsLeft <= 6 ? /* @__PURE__ */ jsxs("span", { className: "inline-flex items-center gap-1 text-red-300", children: [
                    /* @__PURE__ */ jsx(AlertTriangle, { size: 14 }),
                    " nearing forced recheck"
                  ] }) : null
                ] })
              ] })
            ] }),
            /* @__PURE__ */ jsx(RiskBreakdown, { report }),
            /* @__PURE__ */ jsxs("div", { className: "flex flex-wrap gap-2 border-t border-white/10 pt-4", children: [
              /* @__PURE__ */ jsx(MintReportButton, { onClick: onMint, status: mintState.status }),
              /* @__PURE__ */ jsx(
                "button",
                {
                  type: "button",
                  onClick: onRecheck,
                  className: "btn-outline px-4 py-2 text-[11px]",
                  children: "Re-run checks"
                }
              )
            ] }),
            mintState.status === "error" ? /* @__PURE__ */ jsx("p", { className: "text-xs text-red-400", children: mintState.error }) : null
          ] })
        ]
      }
    )
  ] }) : null });
}
const SESSION_PHASE = {
  IDLE: "idle",
  CAPTURING_INTENT: "capturing_intent",
  RUNNING_CHECKS: "running_checks",
  REPORT_READY: "report_ready",
  REPORT_STALE: "report_stale_revalidate_required",
  MINTING: "minting_report",
  MINTED: "minted_ready_to_execute",
  EXECUTING: "executing_tx",
  EXECUTED: "execution_success",
  EXECUTION_FAILED: "execution_failed"
};
const CHECK_STEPS = [
  { id: "intercept", label: "Intercept transaction intent" },
  { id: "decode", label: "Decode calldata + parameters" },
  { id: "offchain", label: "Off-chain simulation (CRE)" },
  { id: "onchain", label: "On-chain guard checks" },
  { id: "report", label: "Risk report generation" }
];
function createInitialTimeline() {
  return CHECK_STEPS.map((step) => ({
    ...step,
    status: "pending",
    message: "",
    startedAt: null,
    endedAt: null
  }));
}
function updateTimelineStep(timeline, stepId, patch) {
  return timeline.map((step) => step.id === stepId ? { ...step, ...patch } : step);
}
function createDefaultIntent() {
  return {
    id: `intent_${Date.now()}`,
    source: "manual-launchpad",
    network: "arbitrum",
    protocol: "Camelot",
    targetUrl: "https://app.camelot.exchange",
    from: "0x1111111111111111111111111111111111111111",
    type: "SWAP",
    opType: "EXACT_TOKENS_IN",
    walletConnectedOnTarget: false,
    updatedAt: Date.now(),
    payload: {
      pair: "WETH/USDC",
      amount: "1.00",
      tokenIn: "WETH",
      tokenOut: "USDC",
      routerAddress: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
      vaultAddress: "0x0000000000000000000000000000000000000000",
      data: "0x",
      notes: ""
    }
  };
}
function normalizeIntent(input) {
  const fallback = createDefaultIntent();
  const merged = {
    ...fallback,
    ...input ?? {},
    payload: {
      ...fallback.payload,
      ...input?.payload ?? {}
    },
    updatedAt: Date.now()
  };
  return merged;
}
function readStoredIntent() {
  return normalizeIntent(readJsonStorage(INTENT_STORAGE_KEY, createDefaultIntent()));
}
function createProtocolIntentBridge({ onIntent }) {
  let channel;
  const emitIntent = (next) => {
    const normalized = normalizeIntent(next);
    writeJsonStorage(INTENT_STORAGE_KEY, normalized);
    onIntent(normalized);
    if (channel) {
      channel.postMessage({ type: "PREFLIGHT_INTENT_UPDATE", payload: normalized });
    }
  };
  const onStorage = (event) => {
    if (event.key !== INTENT_STORAGE_KEY || !event.newValue) return;
    try {
      const parsed = JSON.parse(event.newValue);
      onIntent(normalizeIntent(parsed));
    } catch {
    }
  };
  const onMessage = (event) => {
    const data = event?.data;
    if (!data || typeof data !== "object") return;
    if (data.type === "PREFLIGHT_INTENT_UPDATE") {
      emitIntent(data.payload);
    }
    if (data.type === "PREFLIGHT_WALLET_STATUS") {
      const current = readStoredIntent();
      emitIntent({
        ...current,
        walletConnectedOnTarget: Boolean(data.connected)
      });
    }
  };
  const onWindowMessage = (event) => {
    const data = event?.data;
    if (!data || typeof data !== "object") return;
    if (!String(data.type ?? "").startsWith("PREFLIGHT_")) return;
    onMessage({ data });
  };
  if ("BroadcastChannel" in window) {
    channel = new BroadcastChannel(INTENT_CHANNEL);
    channel.onmessage = onMessage;
  }
  window.addEventListener("storage", onStorage);
  window.addEventListener("message", onWindowMessage);
  return {
    publishIntent: emitIntent,
    disconnect: () => {
      if (channel) channel.close();
      window.removeEventListener("storage", onStorage);
      window.removeEventListener("message", onWindowMessage);
    }
  };
}
function sleep$1(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function randomFrom(str, min, max) {
  const hash = Array.from(str).reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  return min + hash % (max - min + 1);
}
function buildSwapMock(intent) {
  const score = randomFrom(intent.payload.pair ?? "swap", 72, 96);
  const riskLevel = score < 80 ? "WARNING" : "SAFE";
  return {
    isSafe: riskLevel !== "CRITICAL",
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? "EXACT_TOKENS_IN",
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasApprovalDrain: false,
      hasReentrancy: false
    },
    economic: {
      simulationReverted: false,
      actualAmountIn: intent.payload.amount ?? "0",
      oracleDeviation: score < 78,
      priceImpactBps: score < 78 ? 165 : 34,
      tokenInOracleStale: false,
      tokenOutOracleStale: false
    },
    simulatedAt: Math.floor(Date.now() / 1e3),
    network: "arbitrum-mainnet"
  };
}
function buildLiquidityMock(intent) {
  const score = randomFrom(intent.payload.pair ?? "liq", 65, 94);
  const riskLevel = score < 75 ? "WARNING" : "SAFE";
  return {
    isSafe: true,
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? "ADD",
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasOwnerSweep: false,
      hasApprovalDrain: false
    },
    economic: {
      simulationReverted: false,
      isFirstDeposit: false,
      ratioDeviationBps: score < 75 ? 320 : 64,
      isRemovalFrozen: false
    },
    simulatedAt: Math.floor(Date.now() / 1e3),
    network: "arbitrum-mainnet"
  };
}
function buildVaultMock(intent) {
  const score = randomFrom(intent.payload.amount ?? "vault", 58, 91);
  const riskLevel = score < 70 ? "WARNING" : "SAFE";
  return {
    isSafe: riskLevel !== "CRITICAL",
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? "DEPOSIT",
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasOwnerSweep: false,
      hasUpgradeCall: false
    },
    economic: {
      simulationReverted: false,
      outputDiscrepancyBps: score < 70 ? 140 : 28,
      isExitFrozen: false,
      assetOracleStale: false
    },
    simulatedAt: Math.floor(Date.now() / 1e3),
    network: "arbitrum-mainnet"
  };
}
function buildMock(intent) {
  if (intent.type === "LIQUIDITY") return buildLiquidityMock(intent);
  if (intent.type === "VAULT") return buildVaultMock(intent);
  return buildSwapMock(intent);
}
async function runPreflightSimulation(intent, { signal } = {}) {
  {
    await sleep$1(900);
    return buildMock(intent);
  }
}
const DEFAULT_SUMMARY = {
  verdict: "SAFE",
  riskLevel: "SAFE",
  riskScore: 0,
  isSafe: true
};
function normalizeSimulationResult(raw, intent) {
  const base = raw && typeof raw === "object" ? raw : {};
  const summary = {
    verdict: base.riskLevel ?? DEFAULT_SUMMARY.verdict,
    riskLevel: base.riskLevel ?? DEFAULT_SUMMARY.riskLevel,
    riskScore: Number(base.riskScore ?? DEFAULT_SUMMARY.riskScore),
    isSafe: Boolean(base.isSafe ?? DEFAULT_SUMMARY.isSafe)
  };
  return {
    type: intent.type,
    operation: base.operation ?? intent.opType ?? "UNKNOWN",
    network: base.network ?? "arbitrum-mainnet",
    simulatedAt: Number(base.simulatedAt ?? Math.floor(Date.now() / 1e3)),
    summary,
    trace: base.trace ?? {},
    economic: base.economic ?? {},
    raw: base
  };
}
function buildFinalReport({ intent, offchain, onchain }) {
  const riskScore = Number(offchain?.summary?.riskScore ?? 0);
  const riskLevel = offchain?.summary?.riskLevel ?? "SAFE";
  return {
    id: `report_${Date.now()}`,
    createdAt: Date.now(),
    intent,
    offchain,
    onchain,
    final: {
      riskScore,
      riskLevel,
      isSafe: offchain?.summary?.isSafe ?? false,
      verdictText: riskLevel === "CRITICAL" ? "High risk. Abort unless explicitly allowed." : riskLevel === "WARNING" ? "Proceed only after manual confirmation." : "Checks passed within configured policy bounds."
    }
  };
}
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function buildOnchainPlaceholder(intent) {
  return {
    available: false,
    context: intent.type,
    checks: [
      {
        id: "router_guard",
        status: "pending_contracts",
        label: "PreFlightRouter guard contracts are not fully wired yet"
      }
    ]
  };
}
function usePreflightChecks() {
  const [status, setStatus] = useState("idle");
  const [timeline, setTimeline] = useState(createInitialTimeline());
  const [report, setReport] = useState(null);
  const [error, setError] = useState("");
  const reset = () => {
    setStatus("idle");
    setTimeline(createInitialTimeline());
    setReport(null);
    setError("");
  };
  const setStep = (stepId, patch) => {
    setTimeline((prev) => updateTimelineStep(prev, stepId, patch));
  };
  const runChecks = async (intent) => {
    setStatus("running");
    setError("");
    setTimeline(createInitialTimeline());
    try {
      const now = Date.now();
      setStep("intercept", { status: "running", startedAt: now, message: "Intercepting swap/liquidity/vault intent" });
      await sleep(350);
      setStep("intercept", { status: "done", endedAt: Date.now(), message: "Transaction intent captured" });
      setStep("decode", { status: "running", startedAt: Date.now(), message: "Decoding calldata and extracted parameters" });
      await sleep(350);
      setStep("decode", { status: "done", endedAt: Date.now(), message: "Decoded path, amounts, network, and operation type" });
      setStep("offchain", { status: "running", startedAt: Date.now(), message: "Running CRE simulation" });
      const offchainRaw = await runPreflightSimulation(intent);
      const offchain = normalizeSimulationResult(offchainRaw, intent);
      setStep("offchain", { status: "done", endedAt: Date.now(), message: "Off-chain simulation completed" });
      setStep("onchain", { status: "running", startedAt: Date.now(), message: "Evaluating on-chain guards" });
      await sleep(400);
      const onchain = buildOnchainPlaceholder(intent);
      setStep("onchain", { status: "done", endedAt: Date.now(), message: "On-chain checks captured (placeholder)" });
      setStep("report", { status: "running", startedAt: Date.now(), message: "Building final report verdict" });
      await sleep(250);
      const nextReport = buildFinalReport({ intent, offchain, onchain });
      setReport(nextReport);
      setStep("report", { status: "done", endedAt: Date.now(), message: "Risk report ready for user review" });
      setStatus("success");
      return nextReport;
    } catch (err) {
      setStatus("error");
      setError(err?.message ?? "Failed to run checks");
      return null;
    }
  };
  const hasReport = useMemo(() => Boolean(report), [report]);
  return {
    status,
    timeline,
    report,
    error,
    hasReport,
    runChecks,
    reset
  };
}
function useResultFreshness({ isOpen, openedAtMs, ttlMs, onStale }) {
  const [nowMs, setNowMs] = useState(0);
  const staleTriggeredRef = useRef(false);
  useEffect(() => {
    if (!isOpen) {
      staleTriggeredRef.current = false;
      return;
    }
    const timer = setInterval(() => {
      setNowMs(Date.now());
    }, 500);
    return () => clearInterval(timer);
  }, [isOpen]);
  const elapsedMs = useMemo(() => {
    if (!isOpen || !openedAtMs) return 0;
    return Math.max(0, nowMs - openedAtMs);
  }, [isOpen, openedAtMs, nowMs]);
  useEffect(() => {
    if (!isOpen) return;
    if (elapsedMs >= ttlMs && !staleTriggeredRef.current) {
      staleTriggeredRef.current = true;
      onStale?.();
    }
  }, [elapsedMs, isOpen, ttlMs, onStale]);
  const secondsLeft = useMemo(() => Math.max(0, Math.ceil((ttlMs - elapsedMs) / 1e3)), [ttlMs, elapsedMs]);
  return {
    elapsedMs,
    secondsLeft,
    isStale: elapsedMs >= ttlMs
  };
}
async function mintReportNft({ address, report }) {
  {
    return {
      simulated: true,
      tokenId: Date.now(),
      txHash: `sim_mint_${Date.now()}`,
      owner: address,
      report
    };
  }
}
async function executeGuardedTx({ intent, allowRisk = false }) {
  {
    return {
      simulated: true,
      txHash: `sim_exec_${Date.now()}`,
      mode: intent.type
    };
  }
}
function mergeIntent(current, patch) {
  return {
    ...current,
    ...patch,
    payload: {
      ...current?.payload ?? {},
      ...patch?.payload ?? {}
    },
    updatedAt: Date.now()
  };
}
function createMintedSnapshot({ report, mintResult, owner }) {
  return {
    id: `minted_${Date.now()}`,
    mintedAt: Date.now(),
    owner,
    tokenId: mintResult?.tokenId ?? Date.now(),
    txHash: mintResult?.txHash ?? "",
    simulated: Boolean(mintResult?.simulated),
    riskLevel: report?.final?.riskLevel ?? "SAFE",
    riskScore: report?.final?.riskScore ?? 0,
    intentType: report?.intent?.type ?? "UNKNOWN",
    targetUrl: report?.intent?.targetUrl ?? "",
    report
  };
}
function isIntentReady(intent) {
  const from = String(intent?.from ?? "").trim();
  const opType = String(intent?.opType ?? "").trim();
  const data = String(intent?.payload?.data ?? "").trim();
  const amount = String(intent?.payload?.amount ?? "").trim();
  if (!from || !opType || !amount || !data || data === "0x") return false;
  if (intent?.type === "VAULT") {
    return Boolean(String(intent?.payload?.vaultAddress ?? "").trim());
  }
  return Boolean(String(intent?.payload?.routerAddress ?? "").trim());
}
function DexPage({ launchSession, walletGate }) {
  const {
    selectedDex,
    isSidebarOpen,
    isResultOpen,
    setSidebarOpen,
    setResultOpen,
    pushToast,
    addMintedReport
  } = launchSession;
  const [intent, setIntent] = useState(() => readStoredIntent());
  const [sessionPhase, setSessionPhase] = useState(SESSION_PHASE.IDLE);
  const [mintState, setMintState] = useState({ status: "idle", error: "" });
  const [executionState, setExecutionState] = useState({ status: "idle", txHash: "", error: "" });
  const [activeMint, setActiveMint] = useState(null);
  const [resultOpenedAt, setResultOpenedAt] = useState(0);
  const bridgeRef = useRef(null);
  const lastInterceptedDataRef = useRef("");
  const { status, timeline, report, error, runChecks, reset } = usePreflightChecks();
  useEffect(() => {
    const bridge = createProtocolIntentBridge({
      onIntent: (nextIntent) => {
        setIntent(nextIntent);
      }
    });
    bridgeRef.current = bridge;
    return () => bridge.disconnect();
  }, []);
  useEffect(() => {
    if (!selectedDex) return;
    setIntent((current) => {
      const next = mergeIntent(current, {
        targetUrl: selectedDex.url,
        protocol: selectedDex.name,
        network: selectedDex.chain
      });
      bridgeRef.current?.publishIntent(next);
      return next;
    });
  }, [selectedDex]);
  useEffect(() => {
    if (!selectedDex) return;
    const data = String(intent?.payload?.data ?? "").trim();
    if (!data || data === "0x" || data === lastInterceptedDataRef.current) return;
    lastInterceptedDataRef.current = data;
    setSessionPhase(SESSION_PHASE.CAPTURING_INTENT);
    setSidebarOpen(true);
    pushToast("Transaction intercepted", "Captured calldata and parameters. Running checks...");
    const timer = setTimeout(() => {
      runChecksFlow("auto-intercept");
    }, 200);
    return () => clearTimeout(timer);
  }, [intent?.payload?.data, selectedDex]);
  useEffect(() => {
    if (executionState.status !== "success") return void 0;
    const timer = setTimeout(() => {
      setExecutionState({ status: "idle", txHash: "", error: "" });
    }, 3e3);
    return () => clearTimeout(timer);
  }, [executionState.status]);
  const publishIntent = useCallback((patch) => {
    setIntent((current) => {
      const next = mergeIntent(current, patch);
      bridgeRef.current?.publishIntent(next);
      return next;
    });
  }, []);
  const runChecksFlow = useCallback(
    async (origin = "sidebar") => {
      if (status === "running") return;
      setResultOpen(false);
      setMintState({ status: "idle", error: "" });
      setExecutionState({ status: "idle", txHash: "", error: "" });
      setActiveMint(null);
      if (!walletGate.isConnected) {
        pushToast("Wallet not connected", "Connect wallet in PreFlight and the selected DEX page");
        return;
      }
      if (!intent.walletConnectedOnTarget) {
        pushToast("Wallet not connected on DEX", "Enable wallet connection status before checks");
        return;
      }
      setSessionPhase(SESSION_PHASE.RUNNING_CHECKS);
      const nextReport = await runChecks(intent);
      if (!nextReport) {
        setSessionPhase(SESSION_PHASE.IDLE);
        pushToast("PreFlight failed", error || "Check payload fields and try again");
        return;
      }
      setSessionPhase(SESSION_PHASE.REPORT_READY);
      setResultOpenedAt(Date.now());
      setResultOpen(true);
      pushToast("Risk report ready", origin === "auto-intercept" ? "Auto-check completed after intercept" : "Review and mint before execution");
    },
    [status, setResultOpen, walletGate.isConnected, intent, runChecks, pushToast, error]
  );
  const onReportStale = useCallback(async () => {
    if (!isResultOpen || !report || mintState.status === "success") return;
    setSessionPhase(SESSION_PHASE.REPORT_STALE);
    setResultOpen(false);
    pushToast("Report expired (>10s)", "Re-running checks with latest state");
    await runChecksFlow("stale");
  }, [isResultOpen, report, mintState.status, setResultOpen, pushToast, runChecksFlow]);
  const freshness = useResultFreshness({
    isOpen: isResultOpen,
    openedAtMs: resultOpenedAt,
    ttlMs: REPORT_STALE_AFTER_MS,
    onStale: onReportStale
  });
  const handleMint = useCallback(async () => {
    if (!report) return;
    if (freshness.isStale) {
      pushToast("Report stale", "Refreshing checks before minting");
      await runChecksFlow("stale");
      return;
    }
    setMintState({ status: "pending", error: "" });
    setSessionPhase(SESSION_PHASE.MINTING);
    try {
      const mintResult = await mintReportNft({
        address: walletGate.address,
        report
      });
      const snapshot = createMintedSnapshot({
        report,
        mintResult,
        owner: walletGate.address
      });
      addMintedReport(snapshot);
      setActiveMint(snapshot);
      setMintState({ status: "success", error: "" });
      setSessionPhase(SESSION_PHASE.MINTED);
      setResultOpen(false);
      pushToast("RiskReport NFT minted", mintResult.simulated ? "Simulated mint mode" : `Tx: ${mintResult.txHash.slice(0, 10)}...`);
    } catch (err) {
      setMintState({ status: "error", error: err?.message ?? "Mint failed" });
      setSessionPhase(SESSION_PHASE.REPORT_READY);
      pushToast("Mint failed", err?.message ?? "Unknown error");
    }
  }, [report, freshness.isStale, pushToast, runChecksFlow, walletGate.address, addMintedReport, setResultOpen]);
  const handleExecute = useCallback(async () => {
    if (!activeMint) {
      pushToast("Mint required", "Mint RiskReport NFT before execution");
      return;
    }
    setExecutionState({ status: "pending", txHash: "", error: "" });
    setSessionPhase(SESSION_PHASE.EXECUTING);
    try {
      const result = await executeGuardedTx({
        intent,
        allowRisk: report?.final?.riskLevel !== "SAFE"
      });
      setExecutionState({ status: "success", txHash: result.txHash, error: "" });
      setSessionPhase(SESSION_PHASE.EXECUTED);
      pushToast("Transaction successful", "Execution completed through PreFlightRouter");
    } catch (err) {
      setExecutionState({ status: "error", txHash: "", error: err?.message ?? "Execution failed" });
      setSessionPhase(SESSION_PHASE.EXECUTION_FAILED);
      pushToast("Execution failed", err?.message ?? "Unknown error");
    }
  }, [activeMint, pushToast, intent, report]);
  const resetSession = useCallback(() => {
    reset();
    setSessionPhase(SESSION_PHASE.IDLE);
    setMintState({ status: "idle", error: "" });
    setExecutionState({ status: "idle", txHash: "", error: "" });
    setActiveMint(null);
    setResultOpen(false);
    setResultOpenedAt(0);
  }, [reset, setResultOpen]);
  const canRunChecks = useMemo(
    () => walletGate.isConnected && intent.walletConnectedOnTarget && status !== "running",
    [walletGate.isConnected, intent.walletConnectedOnTarget, status]
  );
  const canOpenLauncher = useMemo(() => isIntentReady(intent), [intent]);
  if (!selectedDex) {
    return /* @__PURE__ */ jsxs(Card, { className: "p-8 text-center", children: [
      /* @__PURE__ */ jsx("h2", { className: "text-xl font-black uppercase tracking-[0.12em] text-white", children: "No DEX Selected" }),
      /* @__PURE__ */ jsx("p", { className: "mt-3 text-sm text-slate-400", children: "Go back to Launchpad and choose Camelot or SaucerSwap first." })
    ] });
  }
  return /* @__PURE__ */ jsxs("div", { className: "relative w-full h-[calc(100vh-73px)] min-h-[640px]", children: [
    /* @__PURE__ */ jsx(Card, { className: "relative h-full overflow-hidden rounded-none md:rounded-none p-0 border-x-0 md:border-x-0", children: /* @__PURE__ */ jsxs("div", { className: "absolute inset-0 z-0", children: [
      /* @__PURE__ */ jsxs("div", { className: "absolute top-0 left-0 right-0 h-12 bg-[#111] border-b border-white/10 flex items-center px-4 gap-4 z-20", children: [
        /* @__PURE__ */ jsxs("div", { className: "flex gap-1.5", children: [
          /* @__PURE__ */ jsx("div", { className: "w-3 h-3 rounded-full bg-red-500/50" }),
          /* @__PURE__ */ jsx("div", { className: "w-3 h-3 rounded-full bg-yellow-500/50" }),
          /* @__PURE__ */ jsx("div", { className: "w-3 h-3 rounded-full bg-green-500/50" })
        ] }),
        /* @__PURE__ */ jsx("div", { className: "bg-black/50 px-4 py-1 rounded-md border border-white/5 text-xs text-slate-400 w-full max-w-3xl font-mono break-all", children: selectedDex.url }),
        /* @__PURE__ */ jsxs("div", { className: "ml-auto flex items-center gap-2", children: [
          /* @__PURE__ */ jsx(Badge, { label: selectedDex.name, tone: "info" }),
          /* @__PURE__ */ jsx(
            Button,
            {
              variant: "ghost",
              className: "!px-3 !py-1.5 text-[10px]",
              onClick: () => window.open(selectedDex.url, "_blank", "noopener,noreferrer"),
              children: "Open In New Tab"
            }
          )
        ] })
      ] }),
      /* @__PURE__ */ jsx("div", { className: `h-full w-full pt-12 transition ${isSidebarOpen ? "blur-[2px] brightness-75" : ""}`, children: /* @__PURE__ */ jsx(
        "iframe",
        {
          src: selectedDex.url,
          className: "h-full w-full border-none",
          title: `${selectedDex.name} DEX`,
          referrerPolicy: "no-referrer",
          allow: "clipboard-write; fullscreen"
        }
      ) })
    ] }) }),
    /* @__PURE__ */ jsx(
      FloatingLauncher,
      {
        hidden: isSidebarOpen,
        disabled: !canOpenLauncher,
        onClick: () => {
          if (!canOpenLauncher) {
            pushToast("Complete transaction fields first", "Need calldata, amount, sender, and router/vault address");
            return;
          }
          setSidebarOpen(true);
        }
      }
    ),
    /* @__PURE__ */ jsx(
      SessionSidebar,
      {
        isOpen: isSidebarOpen,
        onClose: () => setSidebarOpen(false),
        intent,
        onIntentPatch: publishIntent,
        walletGate,
        sessionPhase,
        checkStatus: status,
        checkError: error,
        timeline,
        canRunChecks,
        onRunChecks: () => runChecksFlow("sidebar"),
        onViewReport: () => {
          setResultOpenedAt(Date.now());
          setResultOpen(true);
        },
        hasReport: Boolean(report),
        onReset: resetSession,
        mintState,
        mintedReport: activeMint,
        executionState,
        onExecute: handleExecute
      }
    ),
    /* @__PURE__ */ jsx(
      ResultModal,
      {
        isOpen: isResultOpen,
        onClose: () => setResultOpen(false),
        report,
        secondsLeft: freshness.secondsLeft,
        mintState,
        onMint: handleMint,
        onRecheck: () => runChecksFlow("recheck")
      }
    )
  ] });
}
function PortfolioEmptyState({ onConnect, connectError }) {
  return /* @__PURE__ */ jsx(Card, { className: "mx-auto max-w-3xl p-8 md:p-10 text-center", children: /* @__PURE__ */ jsxs("div", { className: "space-y-6", children: [
    /* @__PURE__ */ jsx("div", { className: "mx-auto grid h-16 w-16 place-items-center rounded-2xl border border-brand-cyan/30 bg-brand-cyan/10 text-brand-cyan", children: /* @__PURE__ */ jsx(Wallet, { size: 26 }) }),
    /* @__PURE__ */ jsxs("div", { children: [
      /* @__PURE__ */ jsx("p", { className: "text-[10px] font-black uppercase tracking-[0.24em] text-brand-cyan", children: "Portfolio Locked" }),
      /* @__PURE__ */ jsx("h1", { className: "mt-2 text-2xl font-black uppercase tracking-[0.12em] text-white", children: "My PreFlight Reports & Rewards" }),
      /* @__PURE__ */ jsx("p", { className: "mt-3 text-sm leading-relaxed text-slate-400 max-w-xl mx-auto", children: "Connect wallet to view minted PreFlight report NFTs, historical risk outcomes, and future reward eligibility." })
    ] }),
    /* @__PURE__ */ jsx(Button, { onClick: onConnect, className: "px-8 py-3", children: "Connect Wallet" }),
    connectError ? /* @__PURE__ */ jsxs("div", { className: "inline-flex items-center gap-2 rounded-lg border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs text-red-200", children: [
      /* @__PURE__ */ jsx(ShieldAlert, { size: 14 }),
      connectError
    ] }) : null
  ] }) });
}
function riskTone(level) {
  if (level === "CRITICAL") return "critical";
  if (level === "WARNING") return "warning";
  return "success";
}
function ReportNftGrid({ reports }) {
  if (!reports.length) {
    return /* @__PURE__ */ jsx(Card, { className: "p-6 text-sm text-slate-400", children: "No report NFTs yet. Go to Launchpad, run PreFlight checks, and mint your first report." });
  }
  return /* @__PURE__ */ jsx("section", { className: "grid gap-4 md:grid-cols-2 xl:grid-cols-3", children: reports.map((item) => /* @__PURE__ */ jsxs(Card, { className: "space-y-4 p-5 hover-reveal", children: [
    /* @__PURE__ */ jsxs("div", { className: "flex items-start justify-between gap-3", children: [
      /* @__PURE__ */ jsxs("div", { children: [
        /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black", children: "Report NFT" }),
        /* @__PURE__ */ jsxs("div", { className: "text-xl font-black text-white", children: [
          "#",
          item.tokenId
        ] })
      ] }),
      /* @__PURE__ */ jsx(Badge, { label: item.riskLevel, tone: riskTone(item.riskLevel) })
    ] }),
    /* @__PURE__ */ jsxs("div", { className: "rounded-xl border border-white/10 bg-black/30 p-3 text-xs text-slate-300", children: [
      /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsx(ShieldCheck, { size: 14, className: "text-brand-cyan" }),
        /* @__PURE__ */ jsx("span", { className: "font-bold text-white uppercase tracking-wide", children: item.intentType })
      ] }),
      /* @__PURE__ */ jsx("p", { className: "mt-2 text-slate-400 break-all", children: item.targetUrl || "No target URL captured" }),
      /* @__PURE__ */ jsxs("p", { className: "mt-2 text-[11px] text-slate-500", children: [
        "Minted: ",
        new Date(item.mintedAt).toLocaleString()
      ] })
    ] }),
    /* @__PURE__ */ jsxs("div", { className: "flex items-center justify-between text-xs", children: [
      /* @__PURE__ */ jsx("span", { className: "text-slate-500 uppercase tracking-wider", children: "Risk score" }),
      /* @__PURE__ */ jsx("span", { className: "font-black text-white text-lg leading-none", children: item.riskScore })
    ] }),
    /* @__PURE__ */ jsxs(
      "a",
      {
        className: "inline-flex items-center gap-2 text-xs text-brand-cyan hover:underline",
        href: item.txHash ? `https://arbiscan.io/tx/${item.txHash}` : "#",
        target: "_blank",
        rel: "noreferrer",
        onClick: (event) => {
          if (!item.txHash || String(item.txHash).startsWith("sim_")) {
            event.preventDefault();
          }
        },
        children: [
          "View mint transaction ",
          /* @__PURE__ */ jsx(ExternalLink, { size: 12 })
        ]
      }
    )
  ] }, item.id)) });
}
function calcRewardPoints(reports) {
  return reports.reduce((acc, item) => {
    const base = item.riskLevel === "CRITICAL" ? 30 : item.riskLevel === "WARNING" ? 20 : 10;
    return acc + base;
  }, 0);
}
function RewardSummary({ reports }) {
  const stats = useMemo(() => {
    const total = reports.length;
    const points = calcRewardPoints(reports);
    const safe = reports.filter((item) => item.riskLevel === "SAFE").length;
    return { total, points, safe };
  }, [reports]);
  return /* @__PURE__ */ jsxs("section", { className: "grid gap-3 md:grid-cols-3", children: [
    /* @__PURE__ */ jsxs(Card, { className: "p-5 hover-reveal", children: [
      /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black", children: "Total reports" }),
      /* @__PURE__ */ jsx("div", { className: "mt-3 text-4xl font-black text-white", children: stats.total })
    ] }),
    /* @__PURE__ */ jsxs(Card, { className: "p-5 hover-reveal", children: [
      /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black", children: "Reward points (preview)" }),
      /* @__PURE__ */ jsx("div", { className: "mt-3 text-4xl font-black text-brand-cyan", children: stats.points })
    ] }),
    /* @__PURE__ */ jsxs(Card, { className: "p-5 hover-reveal", children: [
      /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.2em] text-slate-500 font-black", children: "Safe intents" }),
      /* @__PURE__ */ jsx("div", { className: "mt-3 text-4xl font-black text-green-400", children: stats.safe })
    ] })
  ] });
}
function PortfolioPage({ walletGate, mintedReports, clearReports }) {
  if (!walletGate.isConnected) {
    return /* @__PURE__ */ jsx(PortfolioEmptyState, { onConnect: walletGate.connectWallet, connectError: walletGate.error });
  }
  return /* @__PURE__ */ jsxs("section", { className: "space-y-6", children: [
    /* @__PURE__ */ jsx(Card, { className: "p-5 md:p-6", children: /* @__PURE__ */ jsxs("div", { className: "flex flex-wrap items-start justify-between gap-4", children: [
      /* @__PURE__ */ jsxs("div", { children: [
        /* @__PURE__ */ jsx("p", { className: "text-[10px] font-black uppercase tracking-[0.2em] text-brand-cyan", children: "Portfolio Dashboard" }),
        /* @__PURE__ */ jsx("h1", { className: "text-2xl font-black uppercase tracking-[0.1em] text-white mt-1", children: "My PreFlight Reports & Rewards" }),
        /* @__PURE__ */ jsxs("p", { className: "mt-3 text-xs text-slate-400 flex items-center gap-2", children: [
          /* @__PURE__ */ jsx(Wallet, { size: 14, className: "text-brand-cyan" }),
          "Connected wallet: ",
          /* @__PURE__ */ jsx("span", { className: "font-mono text-slate-200", children: walletGate.address })
        ] })
      ] }),
      /* @__PURE__ */ jsx(Button, { variant: "ghost", onClick: clearReports, disabled: !mintedReports.length, children: "Clear Local Report Cache" })
    ] }) }),
    /* @__PURE__ */ jsx(RewardSummary, { reports: mintedReports }),
    /* @__PURE__ */ jsx(ReportNftGrid, { reports: mintedReports })
  ] });
}
function ToastStack({ items }) {
  return /* @__PURE__ */ jsx("div", { className: "fixed top-4 right-4 z-[250] space-y-2 w-[320px]", children: /* @__PURE__ */ jsx(AnimatePresence, { children: items.map((toast) => /* @__PURE__ */ jsxs(
    motion.div,
    {
      initial: { opacity: 0, y: -12, x: 12 },
      animate: { opacity: 1, y: 0, x: 0 },
      exit: { opacity: 0, y: -10, x: 10 },
      className: "rounded-xl border border-white/10 bg-[#101010]/90 backdrop-blur px-4 py-3 text-sm",
      children: [
        /* @__PURE__ */ jsx("div", { className: "font-bold text-white", children: toast.title }),
        toast.message ? /* @__PURE__ */ jsx("div", { className: "text-xs text-slate-400 mt-1", children: toast.message }) : null
      ]
    },
    toast.id
  )) }) });
}
function App() {
  const [route, setRoute] = useState(APP_ROUTES.HOME);
  const launchSession = useLaunchSession();
  const walletGate = useWalletGate();
  const isDexRoute = route === APP_ROUTES.DEX;
  const walletLabel = useMemo(() => {
    if (!walletGate.address) return "Connect Wallet";
    return `${walletGate.address.slice(0, 6)}...${walletGate.address.slice(-4)}`;
  }, [walletGate.address]);
  const navItems = useMemo(() => {
    const items = [{ key: APP_ROUTES.HOME, label: "Launchpad" }];
    if (launchSession.selectedDex) {
      items.push({ key: APP_ROUTES.DEX, label: "DEX" });
    }
    items.push({ key: APP_ROUTES.PORTFOLIO, label: "My PreFlight Reports & Rewards" });
    return items;
  }, [launchSession.selectedDex]);
  const onWalletAction = async () => {
    if (walletGate.isConnected) {
      const result2 = walletGate.disconnectWallet();
      if (result2.ok) {
        launchSession.pushToast("Wallet disconnected");
      } else {
        launchSession.pushToast("Wallet disconnect failed", result2.error);
      }
      return;
    }
    const result = await walletGate.connectWallet();
    if (result.ok) {
      launchSession.pushToast("Wallet connected", "You can now run PreFlight checks");
    } else {
      launchSession.pushToast("Wallet connection failed", result.error);
    }
  };
  return /* @__PURE__ */ jsxs("div", { className: "min-h-screen bg-brand-dark text-slate-100 relative overflow-hidden", children: [
    /* @__PURE__ */ jsx("div", { className: "pointer-events-none absolute inset-0 panel-grid-bg" }),
    /* @__PURE__ */ jsx("div", { className: "pointer-events-none absolute -top-24 -right-24 h-96 w-96 rounded-full bg-brand-cyan/10 blur-3xl" }),
    /* @__PURE__ */ jsx("div", { className: "pointer-events-none absolute -bottom-24 -left-16 h-96 w-96 rounded-full bg-slate-900/50 blur-3xl" }),
    /* @__PURE__ */ jsx("header", { className: "sticky top-0 z-40 border-b border-white/10 bg-brand-dark/90 backdrop-blur-xl", children: /* @__PURE__ */ jsxs("div", { className: "mx-auto flex max-w-7xl items-center gap-4 px-4 py-3 md:px-6", children: [
      /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsx("div", { className: "h-8 w-8 rounded-lg bg-brand-cyan text-black font-black grid place-items-center", children: "P" }),
        /* @__PURE__ */ jsxs("div", { children: [
          /* @__PURE__ */ jsx("div", { className: "text-sm font-black uppercase tracking-[0.22em]", children: APP_NAME }),
          /* @__PURE__ */ jsx("div", { className: "text-[10px] uppercase tracking-[0.16em] text-slate-400", children: NETWORK_LABEL })
        ] })
      ] }),
      /* @__PURE__ */ jsx("nav", { className: "ml-2 flex flex-wrap items-center gap-2", children: navItems.map((item) => /* @__PURE__ */ jsx(
        "button",
        {
          className: `rounded-lg px-3 py-2 text-xs font-bold uppercase tracking-wider transition ${route === item.key ? "bg-white/12 text-white border border-white/20" : "bg-transparent text-slate-400 border border-transparent hover:text-white hover:border-white/15"}`,
          onClick: () => setRoute(item.key),
          children: item.label
        },
        item.key
      )) }),
      /* @__PURE__ */ jsxs("div", { className: "ml-auto flex items-center gap-3", children: [
        /* @__PURE__ */ jsx(Badge, { label: `Reports: ${launchSession.reportCount}`, tone: "info" }),
        /* @__PURE__ */ jsx(Button, { variant: walletGate.isConnected ? "ghost" : "primary", onClick: onWalletAction, children: walletLabel })
      ] })
    ] }) }),
    /* @__PURE__ */ jsxs(
      "main",
      {
        className: `relative z-10 min-h-[calc(100vh-73px)] ${isDexRoute ? "w-full px-0 py-0" : "mx-auto max-w-7xl px-4 py-6 md:px-6 md:py-8"}`,
        children: [
          route === APP_ROUTES.HOME ? /* @__PURE__ */ jsx(LaunchpadPage, { launchSession, onDexSelected: () => setRoute(APP_ROUTES.DEX) }) : null,
          route === APP_ROUTES.DEX ? /* @__PURE__ */ jsx(DexPage, { launchSession, walletGate }) : null,
          route === APP_ROUTES.PORTFOLIO ? /* @__PURE__ */ jsx(
            PortfolioPage,
            {
              walletGate,
              mintedReports: launchSession.mintedReports,
              clearReports: launchSession.clearReports
            }
          ) : null
        ]
      }
    ),
    /* @__PURE__ */ jsx(ToastStack, { items: launchSession.toasts })
  ] });
}
const wagmiConfig = createConfig({
  chains: [arbitrum],
  connectors: [injected()],
  transports: {
    [arbitrum.id]: http()
  }
});
function AppWagmiProvider({ children }) {
  return /* @__PURE__ */ jsx(WagmiProvider, { config: wagmiConfig, children });
}
const queryClient = new QueryClient();
function AppQueryProvider({ children }) {
  return /* @__PURE__ */ jsx(QueryClientProvider, { client: queryClient, children });
}
ReactDOM.createRoot(document.getElementById("root")).render(
  /* @__PURE__ */ jsx(React.StrictMode, { children: /* @__PURE__ */ jsx(AppWagmiProvider, { children: /* @__PURE__ */ jsx(AppQueryProvider, { children: /* @__PURE__ */ jsx(App, {}) }) }) })
);
