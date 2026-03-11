import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import LandingSection from '../features/launchpad/components/LandingSection';
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

export default function LaunchpadPage({ launchSession, walletGate }) {
  const {
    isLaunched,
    isSidebarOpen,
    isResultOpen,
    launch,
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
    if (executionState.status !== 'success') return undefined;
    const timer = setTimeout(() => {
      setExecutionState({ status: 'idle', txHash: '', error: '' });
    }, 4_000);
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
        pushToast('Wallet not connected', 'Connect wallet in PreFlight and the target protocol first');
        return;
      }

      if (!intent.walletConnectedOnTarget) {
        pushToast('Wallet not connected on target', 'Turn on "Wallet connected on target" in sidebar first');
        return;
      }

      setSessionPhase(SESSION_PHASE.RUNNING_CHECKS);
      const nextReport = await runChecks(intent);

      if (!nextReport) {
        setSessionPhase(SESSION_PHASE.IDLE);
        pushToast('PreFlight failed', error || 'Check console/network and try again');
        return;
      }

      setSessionPhase(SESSION_PHASE.REPORT_READY);
      setResultOpenedAt(Date.now());
      setResultOpen(true);
      pushToast('PreFlight report ready', origin === 'stale' ? 'Report revalidated' : 'Review before minting');
    },
    [status, setResultOpen, walletGate.isConnected, intent, runChecks, pushToast, error]
  );

  const onReportStale = useCallback(async () => {
    if (!isResultOpen || !report || mintState.status === 'success') return;

    setSessionPhase(SESSION_PHASE.REPORT_STALE);
    setResultOpen(false);
    pushToast('Report expired (>20s)', 'Re-running checks with latest chain context');

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

      pushToast(
        'Report NFT minted',
        mintResult.simulated ? 'Using simulated mint mode (no NFT address set)' : `Tx: ${mintResult.txHash.slice(0, 10)}...`
      );
    } catch (err) {
      setMintState({ status: 'error', error: err?.message ?? 'Mint failed' });
      setSessionPhase(SESSION_PHASE.REPORT_READY);
      pushToast('Mint failed', err?.message ?? 'Unknown error');
    }
  }, [report, freshness.isStale, pushToast, runChecksFlow, walletGate.address, addMintedReport, setResultOpen]);

  const handleExecute = useCallback(async () => {
    if (!activeMint) {
      pushToast('Mint required', 'Mint report NFT before executing transaction');
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
      pushToast(
        'Transaction executed',
        result.simulated ? 'Simulated execution mode (router address not configured)' : `Tx: ${result.txHash.slice(0, 10)}...`
      );
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

  return (
    <div className="relative min-h-[72vh]">
      <LandingSection
        isLaunched={isLaunched}
        onLaunch={() => {
          if (!isLaunched) {
            launch();
            pushToast('PreFlight launcher activated', 'Floating icon is now active. Click the icon when you are ready.');
            return;
          }

          pushToast('PreFlight already active', 'Use the floating icon to open the sidebar.');
        }}
      />

      {isLaunched ? (
        <FloatingLauncher
          hidden={isSidebarOpen}
          disabled={false}
          onClick={() => {
            setSidebarOpen(true);
            pushToast('PreFlight panel opened', 'Review intent and run checks when ready');
          }}
        />
      ) : null}

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
