import type { CheckResult, NormalizedIntent } from '../shared/types';

const SIMULATION_URL = import.meta.env.VITE_PREFLIGHT_SIM_URL ?? '';

function randomFrom(input: string, min: number, max: number) {
  const hash = Array.from(input).reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  return min + (hash % (max - min + 1));
}

function buildMock(intent: NormalizedIntent): CheckResult {
  const score = randomFrom(`${intent.protocol}:${intent.operationType}:${intent.summary}`, 68, 94);
  const riskLevel = score < 76 ? 'WARNING' : 'SAFE';
  const reasons = [
    `${intent.protocol} adapter decoded ${intent.method}`,
    'CRE endpoint not configured, using deterministic demo verdict',
    intent.chainFamily === 'hedera' ? 'Hedera adapter in compatibility mode' : 'EVM adapter in compatibility mode',
  ];

  return {
    riskLevel,
    riskScore: score,
    reasons,
    offchain: {
      simulatedAt: Date.now(),
      network: intent.networkLabel,
      status: 'mock',
      details: [
        `Intent summary: ${intent.summary}`,
        `Target: ${intent.to}`,
        `Operation: ${intent.operationType}`,
      ],
    },
    onchain: {
      status: 'heuristic',
      details: [
        intent.to ? 'Target contract captured successfully' : 'Target contract missing',
        intent.account ? `User account detected: ${intent.account}` : 'User account not detected yet',
      ],
    },
    freshnessMs: 20_000,
  };
}

export async function runChecks(intent: NormalizedIntent): Promise<CheckResult> {
  if (!SIMULATION_URL) {
    return buildMock(intent);
  }

  const response = await fetch(SIMULATION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      protocol: intent.protocol,
      chainFamily: intent.chainFamily,
      method: intent.method,
      to: intent.to,
      value: intent.value,
      data: intent.data,
      account: intent.account,
      chainId: intent.chainId,
      decoded: intent.decoded,
    }),
  });

  if (!response.ok) {
    throw new Error(`Simulation endpoint failed with status ${response.status}`);
  }

  const body = await response.json();
  return {
    riskLevel: body.riskLevel ?? 'WARNING',
    riskScore: body.riskScore ?? 50,
    reasons: Array.isArray(body.reasons) ? body.reasons : ['CRE endpoint returned a report'],
    offchain: {
      simulatedAt: (body.offchain?.simulatedAt ?? Date.now()) as number,
      network: body.offchain?.network ?? intent.networkLabel,
      status: body.offchain?.status ?? 'ok',
      details: Array.isArray(body.offchain?.details) ? body.offchain.details : ['CRE simulation completed'],
    },
    onchain: {
      status: body.onchain?.status ?? 'pending',
      details: Array.isArray(body.onchain?.details) ? body.onchain.details : ['On-chain checks returned no details'],
    },
    freshnessMs: Number(body.freshnessMs ?? 20_000),
  };
}
