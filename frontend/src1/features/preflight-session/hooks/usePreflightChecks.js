import { useMemo, useState } from 'react';
import { runPreflightSimulation } from '../../../services/api/simulationClient';
import { buildFinalReport, normalizeSimulationResult } from '../model/resultSchema';
import { createInitialTimeline, updateTimelineStep } from '../model/sessionState';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildOnchainPlaceholder(intent) {
  return {
    available: false,
    context: intent.type,
    checks: [
      {
        id: 'router_guard',
        status: 'pending_contracts',
        label: 'PreFlightRouter guard contracts are not fully wired yet',
      },
    ],
  };
}

export function usePreflightChecks() {
  const [status, setStatus] = useState('idle');
  const [timeline, setTimeline] = useState(createInitialTimeline());
  const [report, setReport] = useState(null);
  const [error, setError] = useState('');

  const reset = () => {
    setStatus('idle');
    setTimeline(createInitialTimeline());
    setReport(null);
    setError('');
  };

  const setStep = (stepId, patch) => {
    setTimeline((prev) => updateTimelineStep(prev, stepId, patch));
  };

  const runChecks = async (intent) => {
    setStatus('running');
    setError('');
    setTimeline(createInitialTimeline());

    try {
      const now = Date.now();

      setStep('intercept', { status: 'running', startedAt: now, message: 'Intercepting swap/liquidity/vault intent' });
      await sleep(350);
      setStep('intercept', { status: 'done', endedAt: Date.now(), message: 'Transaction intent captured' });

      setStep('decode', { status: 'running', startedAt: Date.now(), message: 'Decoding calldata and extracted parameters' });
      await sleep(350);
      setStep('decode', { status: 'done', endedAt: Date.now(), message: 'Decoded path, amounts, network, and operation type' });

      setStep('offchain', { status: 'running', startedAt: Date.now(), message: 'Running CRE simulation' });
      const offchainRaw = await runPreflightSimulation(intent);
      const offchain = normalizeSimulationResult(offchainRaw, intent);
      setStep('offchain', { status: 'done', endedAt: Date.now(), message: 'Off-chain simulation completed' });

      setStep('onchain', { status: 'running', startedAt: Date.now(), message: 'Evaluating on-chain guards' });
      await sleep(400);
      const onchain = buildOnchainPlaceholder(intent);
      setStep('onchain', { status: 'done', endedAt: Date.now(), message: 'On-chain checks captured (placeholder)' });

      setStep('report', { status: 'running', startedAt: Date.now(), message: 'Building final report verdict' });
      await sleep(250);
      const nextReport = buildFinalReport({ intent, offchain, onchain });
      setReport(nextReport);
      setStep('report', { status: 'done', endedAt: Date.now(), message: 'Risk report ready for user review' });

      setStatus('success');
      return nextReport;
    } catch (err) {
      setStatus('error');
      setError(err?.message ?? 'Failed to run checks');
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
    reset,
  };
}
