import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import FloatingLauncher from '../features/preflight-session/components/FloatingLauncher';
import SessionSidebar from '../features/preflight-session/components/SessionSidebar';
import ResultModal from '../features/preflight-session/components/ResultModal';
import { SESSION_PHASE } from '../features/preflight-session/model/sessionState';
import { REPORT_STALE_AFTER_MS } from '../shared/constants/app';
import { createProtocolIntentBridge, readStoredIntent } from '../services/adapters/protocolIntentAdapter';
import { usePreflightChecks } from '../features/preflight-session/hooks/usePreflightChecks';
import { useResultFreshness } from '../features/preflight-session/hooks/useResultFreshness';
import { mintReportNft } from '../services/chain/nftClient';
import { executeGuardedTx } from '../services/chain/routerClient';
import Card from '../shared/ui/Card';
import Badge from '../shared/ui/Badge';
import Button from '../shared/ui/Button';

function mergeIntent(current, patch) {
  return {
    ...current,
    ...patch,
    payload: {
      ...(current?.payload ?? {}),
      ...(patch?.payload ?? {}),
    },
    updatedAt: Date.now(),
  };
}

function createMintedSnapshot({ report, mintResult, owner }) {
  return {
    id: `minted_${Date.now()}`,
    mintedAt: Date.now(),
    owner,
    tokenId: mintResult?.tokenId ?? Date.now(),
    txHash: mintResult?.txHash ?? '',
    simulated: Boolean(mintResult?.simulated),
    riskLevel: report?.final?.riskLevel ?? 'SAFE',
    riskScore: report?.final?.riskScore ?? 0,
    intentType: report?.intent?.type ?? 'UNKNOWN',
    targetUrl: report?.intent?.targetUrl ?? '',
    report,
  };
}

function isIntentReady(intent) {
  const from = String(intent?.from ?? '').trim();
  const opType = String(intent?.opType ?? '').trim();
  const data = String(intent?.payload?.data ?? '').trim();
  const amount = String(intent?.payload?.amount ?? '').trim();

  if (!from || !opType || !amount || !data || data === '0x') return false;

  if (intent?.type === 'VAULT') {
    return Boolean(String(intent?.payload?.vaultAddress ?? '').trim());
  }

  return Boolean(String(intent?.payload?.routerAddress ?? '').trim());
}

export default function DexPage({ launchSession, walletGate }) {
  const {
    selectedDex,
    isSidebarOpen,
    isResultOpen,
    setSidebarOpen,
    setResultOpen,
    pushToast,
    addMintedReport,
  } = launchSession;

  const [intent, setIntent] = useState(() => readStoredIntent());
  const [sessionPhase, setSessionPhase] = useState(SESSION_PHASE.IDLE);
  const [mintState, setMintState] = useState({ status: 'idle', error: '' });
  const [executionState, setExecutionState] = useState({ status: 'idle', txHash: '', error: '' });
  const [activeMint, setActiveMint] = useState(null);
  const [resultOpenedAt, setResultOpenedAt] = useState(0);

  const bridgeRef = useRef(null);
  const lastInterceptedDataRef = useRef('');

  const { status, timeline, report, error, runChecks, reset } = usePreflightChecks();

  useEffect(() => {
    const bridge = createProtocolIntentBridge({
      onIntent: (nextIntent) => {
        setIntent(nextIntent);
      },
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
        network: selectedDex.chain,
      });
      bridgeRef.current?.publishIntent(next);
      return next;
    });
  }, [selectedDex]);

  useEffect(() => {
    if (!selectedDex) return;

    const data = String(intent?.payload?.data ?? '').trim();
    if (!data || data === '0x' || data === lastInterceptedDataRef.current) return;

    lastInterceptedDataRef.current = data;
    setSessionPhase(SESSION_PHASE.CAPTURING_INTENT);
    setSidebarOpen(true);
    pushToast('Transaction intercepted', 'Captured calldata and parameters. Running checks...');

    // Start checks automatically after interception.
    const timer = setTimeout(() => {
      runChecksFlow('auto-intercept');
    }, 200);

    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [intent?.payload?.data, selectedDex]);

  useEffect(() => {
    if (executionState.status !== 'success') return undefined;
    const timer = setTimeout(() => {
      setExecutionState({ status: 'idle', txHash: '', error: '' });
    }, 3_000);
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
    async (origin = 'sidebar') => {
      if (status === 'running') return;

      setResultOpen(false);
      setMintState({ status: 'idle', error: '' });
      setExecutionState({ status: 'idle', txHash: '', error: '' });
      setActiveMint(null);

      if (!walletGate.isConnected) {
        pushToast('Wallet not connected', 'Connect wallet in PreFlight and the selected DEX page');
        return;
      }

      if (!intent.walletConnectedOnTarget) {
        pushToast('Wallet not connected on DEX', 'Enable wallet connection status before checks');
        return;
      }

      setSessionPhase(SESSION_PHASE.RUNNING_CHECKS);
      const nextReport = await runChecks(intent);

      if (!nextReport) {
        setSessionPhase(SESSION_PHASE.IDLE);
        pushToast('PreFlight failed', error || 'Check payload fields and try again');
        return;
      }

      setSessionPhase(SESSION_PHASE.REPORT_READY);
      setResultOpenedAt(Date.now());
      setResultOpen(true);
      pushToast('Risk report ready', origin === 'auto-intercept' ? 'Auto-check completed after intercept' : 'Review and mint before execution');
    },
    [status, setResultOpen, walletGate.isConnected, intent, runChecks, pushToast, error]
  );

  const onReportStale = useCallback(async () => {
    if (!isResultOpen || !report || mintState.status === 'success') return;

    setSessionPhase(SESSION_PHASE.REPORT_STALE);
    setResultOpen(false);
    pushToast('Report expired (>10s)', 'Re-running checks with latest state');

    await runChecksFlow('stale');
  }, [isResultOpen, report, mintState.status, setResultOpen, pushToast, runChecksFlow]);

  const freshness = useResultFreshness({
    isOpen: isResultOpen,
    openedAtMs: resultOpenedAt,
    ttlMs: REPORT_STALE_AFTER_MS,
    onStale: onReportStale,
  });

  const handleMint = useCallback(async () => {
    if (!report) return;

    if (freshness.isStale) {
      pushToast('Report stale', 'Refreshing checks before minting');
      await runChecksFlow('stale');
      return;
    }

    setMintState({ status: 'pending', error: '' });
    setSessionPhase(SESSION_PHASE.MINTING);

    try {
      const mintResult = await mintReportNft({
        address: walletGate.address,
        report,
      });

      const snapshot = createMintedSnapshot({
        report,
        mintResult,
        owner: walletGate.address,
      });

      addMintedReport(snapshot);
      setActiveMint(snapshot);
      setMintState({ status: 'success', error: '' });
      setSessionPhase(SESSION_PHASE.MINTED);
      setResultOpen(false);

      pushToast('RiskReport NFT minted', mintResult.simulated ? 'Simulated mint mode' : `Tx: ${mintResult.txHash.slice(0, 10)}...`);
    } catch (err) {
      setMintState({ status: 'error', error: err?.message ?? 'Mint failed' });
      setSessionPhase(SESSION_PHASE.REPORT_READY);
      pushToast('Mint failed', err?.message ?? 'Unknown error');
    }
  }, [report, freshness.isStale, pushToast, runChecksFlow, walletGate.address, addMintedReport, setResultOpen]);

  const handleExecute = useCallback(async () => {
    if (!activeMint) {
      pushToast('Mint required', 'Mint RiskReport NFT before execution');
      return;
    }

    setExecutionState({ status: 'pending', txHash: '', error: '' });
    setSessionPhase(SESSION_PHASE.EXECUTING);

    try {
      const result = await executeGuardedTx({
        intent,
        allowRisk: report?.final?.riskLevel !== 'SAFE',
      });

      setExecutionState({ status: 'success', txHash: result.txHash, error: '' });
      setSessionPhase(SESSION_PHASE.EXECUTED);
      pushToast('Transaction successful', 'Execution completed through PreFlightRouter');
    } catch (err) {
      setExecutionState({ status: 'error', txHash: '', error: err?.message ?? 'Execution failed' });
      setSessionPhase(SESSION_PHASE.EXECUTION_FAILED);
      pushToast('Execution failed', err?.message ?? 'Unknown error');
    }
  }, [activeMint, pushToast, intent, report]);

  const resetSession = useCallback(() => {
    reset();
    setSessionPhase(SESSION_PHASE.IDLE);
    setMintState({ status: 'idle', error: '' });
    setExecutionState({ status: 'idle', txHash: '', error: '' });
    setActiveMint(null);
    setResultOpen(false);
    setResultOpenedAt(0);
  }, [reset, setResultOpen]);

  const canRunChecks = useMemo(
    () => walletGate.isConnected && intent.walletConnectedOnTarget && status !== 'running',
    [walletGate.isConnected, intent.walletConnectedOnTarget, status]
  );

  const canOpenLauncher = useMemo(() => isIntentReady(intent), [intent]);

  if (!selectedDex) {
    return (
      <Card className="p-8 text-center">
        <h2 className="text-xl font-black uppercase tracking-[0.12em] text-white">No DEX Selected</h2>
        <p className="mt-3 text-sm text-slate-400">Go back to Launchpad and choose Camelot or SaucerSwap first.</p>
      </Card>
    );
  }

  return (
    <div className="relative w-full h-[calc(100vh-73px)] min-h-[640px]">
      <Card className="relative h-full overflow-hidden rounded-none md:rounded-none p-0 border-x-0 md:border-x-0">
        <div className="absolute inset-0 z-0">
          <div className="absolute top-0 left-0 right-0 h-12 bg-[#111] border-b border-white/10 flex items-center px-4 gap-4 z-20">
            <div className="flex gap-1.5">
              <div className="w-3 h-3 rounded-full bg-red-500/50" />
              <div className="w-3 h-3 rounded-full bg-yellow-500/50" />
              <div className="w-3 h-3 rounded-full bg-green-500/50" />
            </div>
            <div className="bg-black/50 px-4 py-1 rounded-md border border-white/5 text-xs text-slate-400 w-full max-w-3xl font-mono break-all">
              {selectedDex.url}
            </div>
            <div className="ml-auto flex items-center gap-2">
              <Badge label={selectedDex.name} tone="info" />
              <Button
                variant="ghost"
                className="!px-3 !py-1.5 text-[10px]"
                onClick={() => window.open(selectedDex.url, '_blank', 'noopener,noreferrer')}
              >
                Open In New Tab
              </Button>
            </div>
          </div>

          <div className={`h-full w-full pt-12 transition ${isSidebarOpen ? 'blur-[2px] brightness-75' : ''}`}>
            <iframe
              src={selectedDex.url}
              className="h-full w-full border-none"
              title={`${selectedDex.name} DEX`}
              referrerPolicy="no-referrer"
              allow="clipboard-write; fullscreen"
            />
          </div>
        </div>
      </Card>

      <FloatingLauncher
        hidden={isSidebarOpen}
        disabled={!canOpenLauncher}
        onClick={() => {
          if (!canOpenLauncher) {
            pushToast('Complete transaction fields first', 'Need calldata, amount, sender, and router/vault address');
            return;
          }
          setSidebarOpen(true);
        }}
      />

      <SessionSidebar
        isOpen={isSidebarOpen}
        onClose={() => setSidebarOpen(false)}
        intent={intent}
        onIntentPatch={publishIntent}
        walletGate={walletGate}
        sessionPhase={sessionPhase}
        checkStatus={status}
        checkError={error}
        timeline={timeline}
        canRunChecks={canRunChecks}
        onRunChecks={() => runChecksFlow('sidebar')}
        onViewReport={() => {
          setResultOpenedAt(Date.now());
          setResultOpen(true);
        }}
        hasReport={Boolean(report)}
        onReset={resetSession}
        mintState={mintState}
        mintedReport={activeMint}
        executionState={executionState}
        onExecute={handleExecute}
      />

      <ResultModal
        isOpen={isResultOpen}
        onClose={() => setResultOpen(false)}
        report={report}
        secondsLeft={freshness.secondsLeft}
        mintState={mintState}
        onMint={handleMint}
        onRecheck={() => runChecksFlow('recheck')}
      />
    </div>
  );
}
