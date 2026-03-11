import { ethers } from 'ethers';

const SIMULATION_URL = import.meta.env.VITE_PREFLIGHT_SIM_URL ?? '';
const SIMULATION_FORMAT = (import.meta.env.VITE_PREFLIGHT_SIM_FORMAT ?? 'cre').toLowerCase();

const DEFAULT_ADDR = {
  user: '0x1111111111111111111111111111111111111111',
  router: '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
  vault: '0x0000000000000000000000000000000000000000',
  weth: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1',
  usdc: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8',
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomFrom(str, min, max) {
  const hash = Array.from(str).reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  return min + (hash % (max - min + 1));
}

function normalizeAddress(value, fallback) {
  const candidate = String(value ?? '').trim();
  if (/^0x[a-fA-F0-9]{40}$/.test(candidate)) return candidate;
  return fallback;
}

function toBaseUnit(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return '0';
  if (/^[0-9]+$/.test(raw)) return raw;

  try {
    return ethers.parseUnits(raw, 18).toString();
  } catch {
    return '0';
  }
}

function normalizeData(value) {
  const data = String(value ?? '').trim();
  if (!data) return '0x';
  if (data.startsWith('0x')) return data;
  return `0x${data}`;
}

function normalizePath(pathInput, tokenInAddress, tokenOutAddress) {
  if (Array.isArray(pathInput) && pathInput.length >= 2) {
    return pathInput.map((item) => normalizeAddress(item, DEFAULT_ADDR.weth));
  }

  if (typeof pathInput === 'string' && pathInput.includes(',')) {
    const list = pathInput
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => normalizeAddress(item, DEFAULT_ADDR.weth));

    if (list.length >= 2) return list;
  }

  return [
    normalizeAddress(tokenInAddress, DEFAULT_ADDR.weth),
    normalizeAddress(tokenOutAddress, DEFAULT_ADDR.usdc),
  ];
}

function toCrePayload(intent) {
  const payload = intent?.payload ?? {};
  const from = normalizeAddress(intent?.from ?? payload?.from, DEFAULT_ADDR.user);
  const opType = String(intent?.opType ?? 'EXACT_TOKENS_IN').toUpperCase();

  if (intent?.type === 'LIQUIDITY') {
    return {
      type: 'LIQUIDITY',
      opType,
      from,
      routerAddress: normalizeAddress(payload.routerAddress, DEFAULT_ADDR.router),
      data: normalizeData(payload.data),
      tokenA: normalizeAddress(payload.tokenA ?? payload.tokenInAddress, DEFAULT_ADDR.weth),
      tokenB: normalizeAddress(payload.tokenB ?? payload.tokenOutAddress, DEFAULT_ADDR.usdc),
      amountADesired: toBaseUnit(payload.amountADesired ?? payload.amount),
      amountBDesired: toBaseUnit(payload.amountBDesired ?? payload.amountOutMin ?? '0'),
      amountAMin: toBaseUnit(payload.amountAMin ?? '0'),
      amountBMin: toBaseUnit(payload.amountBMin ?? '0'),
      to: normalizeAddress(payload.to, from),
      ethValue: String(payload.ethValue ?? '0'),
    };
  }

  if (intent?.type === 'VAULT') {
    return {
      type: 'VAULT',
      opType,
      from,
      vaultAddress: normalizeAddress(payload.vaultAddress, DEFAULT_ADDR.vault),
      amount: toBaseUnit(payload.amount),
      data: normalizeData(payload.data),
      receiver: normalizeAddress(payload.receiver, from),
    };
  }

  const path = normalizePath(payload.path, payload.tokenInAddress, payload.tokenOutAddress);

  return {
    type: 'SWAP',
    opType,
    from,
    routerAddress: normalizeAddress(payload.routerAddress, DEFAULT_ADDR.router),
    data: normalizeData(payload.data),
    path,
    amountIn: toBaseUnit(payload.amountIn ?? payload.amount),
    amountOutMin: toBaseUnit(payload.amountOutMin ?? '0'),
    amountOut: toBaseUnit(payload.amountOut ?? '0'),
    amountInMax: toBaseUnit(payload.amountInMax ?? '0'),
    ethValue: String(payload.ethValue ?? '0'),
  };
}

function normalizeRemoteResponse(raw) {
  if (!raw || typeof raw !== 'object') return raw;
  if (raw.result && typeof raw.result === 'object') return raw.result;
  if (raw.data && typeof raw.data === 'object') {
    if (raw.data.result && typeof raw.data.result === 'object') return raw.data.result;
    return raw.data;
  }
  return raw;
}

function buildSwapMock(intent) {
  const score = randomFrom(intent.payload.pair ?? 'swap', 72, 96);
  const riskLevel = score < 80 ? 'WARNING' : 'SAFE';

  return {
    isSafe: riskLevel !== 'CRITICAL',
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? 'EXACT_TOKENS_IN',
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasApprovalDrain: false,
      hasReentrancy: false,
    },
    economic: {
      simulationReverted: false,
      actualAmountIn: intent.payload.amount ?? '0',
      oracleDeviation: score < 78,
      priceImpactBps: score < 78 ? 165 : 34,
      tokenInOracleStale: false,
      tokenOutOracleStale: false,
    },
    simulatedAt: Math.floor(Date.now() / 1000),
    network: 'arbitrum-mainnet',
  };
}

function buildLiquidityMock(intent) {
  const score = randomFrom(intent.payload.pair ?? 'liq', 65, 94);
  const riskLevel = score < 75 ? 'WARNING' : 'SAFE';

  return {
    isSafe: true,
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? 'ADD',
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasOwnerSweep: false,
      hasApprovalDrain: false,
    },
    economic: {
      simulationReverted: false,
      isFirstDeposit: false,
      ratioDeviationBps: score < 75 ? 320 : 64,
      isRemovalFrozen: false,
    },
    simulatedAt: Math.floor(Date.now() / 1000),
    network: 'arbitrum-mainnet',
  };
}

function buildVaultMock(intent) {
  const score = randomFrom(intent.payload.amount ?? 'vault', 58, 91);
  const riskLevel = score < 70 ? 'WARNING' : 'SAFE';

  return {
    isSafe: riskLevel !== 'CRITICAL',
    riskLevel,
    riskScore: score,
    operation: intent.opType ?? 'DEPOSIT',
    trace: {
      hasDangerousDelegateCall: false,
      hasSelfDestruct: false,
      hasOwnerSweep: false,
      hasUpgradeCall: false,
    },
    economic: {
      simulationReverted: false,
      outputDiscrepancyBps: score < 70 ? 140 : 28,
      isExitFrozen: false,
      assetOracleStale: false,
    },
    simulatedAt: Math.floor(Date.now() / 1000),
    network: 'arbitrum-mainnet',
  };
}

function buildMock(intent) {
  if (intent.type === 'LIQUIDITY') return buildLiquidityMock(intent);
  if (intent.type === 'VAULT') return buildVaultMock(intent);
  return buildSwapMock(intent);
}

export async function runPreflightSimulation(intent, { signal } = {}) {
  if (!SIMULATION_URL) {
    await sleep(900);
    return buildMock(intent);
  }

  const payload = SIMULATION_FORMAT === 'intent' ? intent : toCrePayload(intent);

  const response = await fetch(SIMULATION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Simulation API failed (${response.status}): ${text.slice(0, 180)}`);
  }

  const body = await response.json();
  return normalizeRemoteResponse(body);
}
