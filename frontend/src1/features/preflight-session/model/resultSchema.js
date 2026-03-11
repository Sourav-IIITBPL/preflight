const DEFAULT_SUMMARY = {
  verdict: 'SAFE',
  riskLevel: 'SAFE',
  riskScore: 0,
  isSafe: true,
};

export function normalizeSimulationResult(raw, intent) {
  const base = raw && typeof raw === 'object' ? raw : {};

  const summary = {
    verdict: base.riskLevel ?? DEFAULT_SUMMARY.verdict,
    riskLevel: base.riskLevel ?? DEFAULT_SUMMARY.riskLevel,
    riskScore: Number(base.riskScore ?? DEFAULT_SUMMARY.riskScore),
    isSafe: Boolean(base.isSafe ?? DEFAULT_SUMMARY.isSafe),
  };

  return {
    type: intent.type,
    operation: base.operation ?? intent.opType ?? 'UNKNOWN',
    network: base.network ?? 'arbitrum-mainnet',
    simulatedAt: Number(base.simulatedAt ?? Math.floor(Date.now() / 1000)),
    summary,
    trace: base.trace ?? {},
    economic: base.economic ?? {},
    raw: base,
  };
}

export function buildFinalReport({ intent, offchain, onchain }) {
  const riskScore = Number(offchain?.summary?.riskScore ?? 0);
  const riskLevel = offchain?.summary?.riskLevel ?? 'SAFE';

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
      verdictText:
        riskLevel === 'CRITICAL'
          ? 'High risk. Abort unless explicitly allowed.'
          : riskLevel === 'WARNING'
            ? 'Proceed only after manual confirmation.'
            : 'Checks passed within configured policy bounds.',
    },
  };
}
