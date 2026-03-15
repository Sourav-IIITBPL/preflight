import { useCallback, useEffect, useMemo, useState } from 'react';
import { ethers } from 'ethers';
import { REPORT_STORAGE_KEY } from '../constants';
import { CONTRACTS, RISK_REPORT_NFT_ABI } from '../lib/contracts';
import { readJsonStorage, writeJsonStorage } from '../lib/storage';

const reportTypeLabel = ['Vault Deposit', 'Vault Redeem', 'Swap V2', 'Swap V3', 'Swap V4'];
const riskLevelLabel = ['SAFE', 'WARNING', 'CRITICAL'];
const statusLabel = ['PENDING', 'CONSUMED', 'EXPIRED'];

function formatAmount(value) {
  try {
    return ethers.formatUnits(value ?? 0n, 18);
  } catch {
    return String(value ?? '0');
  }
}

function normalizeLocalReport(item) {
  return {
    id: item.id ?? `local_${item.tokenId ?? Date.now()}`,
    source: 'local',
    tokenId: item.tokenId ?? 'Preview',
    riskLevel: item.riskLevel ?? 'SAFE',
    riskScore: item.riskScore ?? 0,
    intentType: item.intentType ?? 'Intent',
    targetUrl: item.targetUrl ?? '',
    mintedAt: item.mintedAt ?? Date.now(),
    txHash: item.txHash ?? '',
    status: item.status ?? 'PENDING',
    target: item.target ?? '',
    router: item.router ?? '',
    amount: item.amount ?? '0',
  };
}

function normalizeOnchainReport(tokenId, report) {
  return {
    id: `chain_${tokenId}`,
    source: 'onchain',
    tokenId: tokenId.toString(),
    riskLevel: riskLevelLabel[Number(report.riskLevel)] ?? 'SAFE',
    riskScore: Number(report.criticalCount) * 35 + Number(report.softCount) * 10,
    intentType: reportTypeLabel[Number(report.reportType)] ?? 'Risk Report',
    targetUrl: '',
    mintedAt: Number(report.timestamp) * 1000,
    txHash: '',
    status: statusLabel[Number(report.status)] ?? 'PENDING',
    target: report.target,
    router: report.router,
    amount: formatAmount(report.amount),
    blockNumber: report.blockNumber?.toString?.() ?? String(report.blockNumber ?? ''),
    criticalCount: Number(report.criticalCount),
    softCount: Number(report.softCount),
  };
}

export function usePortfolioReports({ address, isConnected }) {
  const [localReports, setLocalReports] = useState(() => {
    const cached = readJsonStorage(REPORT_STORAGE_KEY, []);
    return Array.isArray(cached) ? cached.map(normalizeLocalReport) : [];
  });
  const [onchainReports, setOnchainReports] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    writeJsonStorage(REPORT_STORAGE_KEY, localReports);
  }, [localReports]);

  const refreshOnchain = useCallback(async () => {
    if (!isConnected || !address) {
      setOnchainReports([]);
      setError('');
      return [];
    }

    if (!CONTRACTS.riskReportNft) {
      setOnchainReports([]);
      setError('Set VITE_PREFLIGHT_REPORT_NFT_ADDRESS to enable on-chain report sync.');
      return [];
    }

    try {
      setIsLoading(true);
      setError('');

      // Use window.ethereum if connected, otherwise fallback to public RPC
      const provider = window.ethereum && isConnected
        ? new ethers.BrowserProvider(window.ethereum)
        : new ethers.JsonRpcProvider(CONTRACTS.rpcUrl);
        
      const contract = new ethers.Contract(CONTRACTS.riskReportNft, RISK_REPORT_NFT_ABI, provider);

      // 1. Get balance
      const balance = Number(await contract.balanceOf(address));
      if (balance === 0) {
        setOnchainReports([]);
        return [];
      }

      // 2. Fetch token IDs and reports in parallel for better performance
      const cappedBalance = Math.min(balance, 50);
      
      // We fetch token IDs first
      const tokenIdPromises = [];
      for (let i = 0; i < cappedBalance; i++) {
        tokenIdPromises.push(contract.tokenOfOwnerByIndex(address, i));
      }
      const tokenIds = await Promise.all(tokenIdPromises);

      // Then we fetch all reports in parallel
      const reportPromises = tokenIds.map(id => contract.getReport(id));
      const reports = await Promise.all(reportPromises);

      const next = tokenIds.map((id, i) => normalizeOnchainReport(id, reports[i]));

      next.sort((a, b) => b.mintedAt - a.mintedAt);
      setOnchainReports(next);
      return next;
    } catch (err) {
      console.error('Portfolio load error:', err);
      const message = err?.message ?? 'Failed to load on-chain reports';
      setOnchainReports([]);
      setError(message);
      return [];
    } finally {
      setIsLoading(false);
    }
  }, [address, isConnected]);

  useEffect(() => {
    refreshOnchain();
  }, [refreshOnchain]);

  const clearLocalReports = useCallback(() => {
    setLocalReports([]);
    writeJsonStorage(REPORT_STORAGE_KEY, []);
  }, []);

  const summary = useMemo(() => {
    const merged = [...onchainReports, ...localReports];
    const safeCount = merged.filter((item) => item.riskLevel === 'SAFE').length;
    const points = merged.reduce((acc, item) => {
      if (item.riskLevel === 'CRITICAL') return acc + 30;
      if (item.riskLevel === 'WARNING') return acc + 20;
      return acc + 10;
    }, 0);

    return {
      total: merged.length,
      onchain: onchainReports.length,
      local: localReports.length,
      safe: safeCount,
      points,
    };
  }, [localReports, onchainReports]);

  return {
    localReports,
    onchainReports,
    isLoading,
    error,
    summary,
    clearLocalReports,
    refreshOnchain,
  };
}
