import type { CheckResult, NormalizedIntent, SiteContext, SiteSession, StoredReport } from '../shared/types';
import { normalizeCamelotIntent } from '../adapters/camelot/normalize';
import { normalizeSaucerSwapIntent } from '../adapters/saucerswap/normalize';
import { detectSupportedSite } from './pageDetector';
import { PreflightOverlay } from './uiBridge';

const site = detectSupportedSite(window.location.href);

if (site) {
  const overlay = new PreflightOverlay(site, {
    onActivate: () => activate(),
    onRunChecks: () => void runChecks(),
    onMint: () => void mintReport(),
    onExecute: () => void executeIntent(),
    onDismissReport: () => overlay.closeReport(),
  });

  const overlayState = {
    site,
    activated: false,
    walletConnected: false,
    account: undefined as string | undefined,
    chainId: undefined as string | undefined,
    intent: undefined as NormalizedIntent | undefined,
    report: undefined as CheckResult | undefined,
  };

  injectScript();
  syncSiteState();

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || typeof message !== 'object') return;

    if (message.type === 'PF_ACTIVATE_SITE') {
      activate();
      sendResponse({ ok: true });
      return true;
    }

    if (message.type === 'PF_GET_PAGE_STATE') {
      sendResponse({
        ok: true,
        activated: overlayState.activated,
        walletConnected: overlayState.walletConnected,
        account: overlayState.account,
        chainId: overlayState.chainId,
        site: overlayState.site,
        intentSummary: overlayState.intent?.summary,
      });
      return true;
    }
  });

  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object' || data.source !== 'preflight-injected') return;

    if (data.type === 'PF_PROVIDER_READY') {
      overlayState.walletConnected = Boolean(data.payload?.walletAvailable);
      overlay.setWalletConnected(overlayState.walletConnected, overlayState.account);
      void syncSiteState();
      return;
    }

    if (data.type === 'PF_PROVIDER_STATUS') {
      overlayState.walletConnected = Boolean(data.payload?.walletConnected);
      overlayState.account = typeof data.payload?.account === 'string' ? data.payload.account : overlayState.account;
      overlayState.chainId = typeof data.payload?.chainId === 'string' ? data.payload.chainId : overlayState.chainId;
      overlay.setWalletConnected(overlayState.walletConnected, overlayState.account);
      void syncSiteState();
      return;
    }

    if (data.type === 'PF_PROVIDER_INTERCEPTED') {
      const normalized = normalizeIntent(site, data.payload as Record<string, unknown>);
      overlayState.intent = normalized;
      overlay.setIntent(normalized);
      void syncSiteState(normalized);
      return;
    }

    if (data.type === 'PF_EXECUTION_RESULT') {
      if (data.payload?.ok) {
        overlay.setExecutionState('success', `Execution request sent: ${String(data.payload.hash ?? 'pending hash')}`);
      } else {
        overlay.setExecutionState('error', String(data.payload?.error ?? 'Execution failed in page context'));
      }
    }
  });

  function normalizeIntent(currentSite: SiteContext, payload: Record<string, unknown>): NormalizedIntent {
    if (currentSite.protocol === 'camelot') return normalizeCamelotIntent(currentSite, payload);
    return normalizeSaucerSwapIntent(currentSite, payload);
  }

  function injectScript() {
    const script = document.createElement('script');
    script.src = chrome.runtime.getURL('injected.js');
    script.async = false;
    (document.head || document.documentElement).appendChild(script);
    script.remove();
  }

  function activate() {
    overlayState.activated = true;
    overlay.setActivated(true);
    window.postMessage({ source: 'preflight-content', type: 'PF_INJECTED_SET_ACTIVE', payload: { active: true } }, '*');
    void syncSiteState();
  }

  async function runChecks() {
    if (!overlayState.intent) return;
    overlay.setChecking('Submitting normalized payload to background checks');
    try {
      const report = (await chrome.runtime.sendMessage({ type: 'PF_RUN_CHECKS', payload: overlayState.intent })) as CheckResult;
      overlayState.report = report;
      overlay.setReport(report);
      await syncSiteState(overlayState.intent, report);
    } catch (error) {
      overlay.setExecutionState('error', error instanceof Error ? error.message : 'Check pipeline failed');
    }
  }

  async function mintReport() {
    if (!overlayState.intent || !overlayState.report) return;
    overlay.setMintState('pending');
    const report: StoredReport = {
      id: `report_${Date.now()}`,
      protocol: overlayState.intent.protocol,
      operationType: overlayState.intent.operationType,
      riskLevel: overlayState.report.riskLevel,
      riskScore: overlayState.report.riskScore,
      summary: overlayState.intent.summary,
      account: overlayState.intent.account,
      target: overlayState.intent.to,
      createdAt: Date.now(),
      source: 'extension-local',
    };

    await chrome.runtime.sendMessage({ type: 'PF_STORE_REPORT', payload: report });
    overlay.setMintState('success');
  }

  async function executeIntent() {
    if (!overlayState.intent) return;
    overlay.setExecutionState('pending', 'Re-submitting the captured transaction into the page wallet context');
    window.postMessage({
      source: 'preflight-content',
      type: 'PF_INJECTED_EXECUTE_ORIGINAL',
      payload: { tx: overlayState.intent.rawTx },
    }, '*');
  }

  async function syncSiteState(intent?: NormalizedIntent, report?: CheckResult) {
    const payload: SiteSession = {
      protocol: overlayState.site.protocol,
      host: overlayState.site.host,
      url: window.location.href,
      activated: overlayState.activated,
      account: overlayState.account,
      chainId: overlayState.chainId,
      lastIntentSummary: intent?.summary ?? overlayState.intent?.summary,
      lastRiskLevel: report?.riskLevel ?? overlayState.report?.riskLevel,
      updatedAt: Date.now(),
    };

    await chrome.runtime.sendMessage({ type: 'PF_SET_SITE_STATE', payload });
  }
}
