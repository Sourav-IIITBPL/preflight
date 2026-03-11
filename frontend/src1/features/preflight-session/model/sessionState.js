export const SESSION_PHASE = {
  IDLE: 'idle',
  CAPTURING_INTENT: 'capturing_intent',
  RUNNING_CHECKS: 'running_checks',
  REPORT_READY: 'report_ready',
  REPORT_STALE: 'report_stale_revalidate_required',
  MINTING: 'minting_report',
  MINTED: 'minted_ready_to_execute',
  EXECUTING: 'executing_tx',
  EXECUTED: 'execution_success',
  EXECUTION_FAILED: 'execution_failed',
};

export const CHECK_STEPS = [
  { id: 'intercept', label: 'Intercept transaction intent' },
  { id: 'decode', label: 'Decode calldata + parameters' },
  { id: 'offchain', label: 'Off-chain simulation (CRE)' },
  { id: 'onchain', label: 'On-chain guard checks' },
  { id: 'report', label: 'Risk report generation' },
];

export function createInitialTimeline() {
  return CHECK_STEPS.map((step) => ({
    ...step,
    status: 'pending',
    message: '',
    startedAt: null,
    endedAt: null,
  }));
}

export function updateTimelineStep(timeline, stepId, patch) {
  return timeline.map((step) => (step.id === stepId ? { ...step, ...patch } : step));
}
