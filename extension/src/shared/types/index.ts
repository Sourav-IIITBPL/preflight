export type ProtocolId = 'camelot' | 'saucerswap';
export type ChainFamily = 'evm' | 'hedera';
export type RiskLevel = 'SAFE' | 'WARNING' | 'CRITICAL';

export interface SiteContext {
  protocol: ProtocolId;
  chainFamily: ChainFamily;
  chainLabel: string;
  host: string;
  url: string;
}

export interface NormalizedIntent {
  id: string;
  protocol: ProtocolId;
  chainFamily: ChainFamily;
  networkLabel: string;
  operationType: string;
  method: string;
  account?: string;
  chainId?: string;
  to: string;
  value: string;
  data: string;
  summary: string;
  decoded: {
    tokenIn?: string;
    tokenOut?: string;
    path?: string[];
    amountIn?: string;
    amountOutMin?: string;
    liquidityTarget?: string;
    notes?: string[];
  };
  rawTx: Record<string, unknown>;
  interceptedAt: number;
}

export interface CheckResult {
  riskLevel: RiskLevel;
  riskScore: number;
  reasons: string[];
  offchain: {
    simulatedAt: number;
    network: string;
    status: string;
    details: string[];
  };
  onchain: {
    status: string;
    details: string[];
  };
  freshnessMs: number;
}

export interface StoredReport {
  id: string;
  protocol: ProtocolId;
  operationType: string;
  riskLevel: RiskLevel;
  riskScore: number;
  summary: string;
  account?: string;
  target: string;
  createdAt: number;
  source: 'extension-local';
}

export interface SiteSession {
  tabId?: number;
  protocol: ProtocolId;
  host: string;
  url: string;
  activated: boolean;
  account?: string;
  chainId?: string;
  lastIntentSummary?: string;
  lastRiskLevel?: RiskLevel;
  updatedAt: number;
}
