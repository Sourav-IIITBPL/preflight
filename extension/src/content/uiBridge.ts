import type { CheckResult, NormalizedIntent, SiteContext } from '../shared/types';

interface OverlayHandlers {
  onActivate(): void;
  onRunChecks(): void;
  onMint(): void;
  onExecute(): void;
  onDismissReport(): void;
}

interface OverlayState {
  activated: boolean;
  sidebarOpen: boolean;
  reportOpen: boolean;
  statusMessage: string;
  intent?: NormalizedIntent;
  report?: CheckResult;
  timeline: Array<{ label: string; status: 'idle' | 'active' | 'done' | 'error'; detail?: string }>;
  walletConnected: boolean;
  executionState: 'idle' | 'pending' | 'success' | 'error';
  mintState: 'idle' | 'pending' | 'success' | 'error';
}

const BASE_STYLE = `
:host { all: initial; }
* { box-sizing: border-box; }
.preflight-shell { position: fixed; inset: 0; pointer-events: none; z-index: 2147483646; font-family: Sora, Inter, system-ui, sans-serif; }
.preflight-fab { position: fixed; right: 24px; bottom: 24px; width: 64px; height: 64px; border-radius: 18px; border: 1px solid rgba(0,242,254,.35); background: linear-gradient(180deg, rgba(0,242,254,.95), rgba(79,172,254,.92)); color: #000; display: grid; place-items: center; font-weight: 900; letter-spacing: .18em; text-transform: uppercase; box-shadow: 0 0 32px rgba(0,242,254,.32); cursor: pointer; pointer-events: auto; }
.preflight-fab[disabled] { opacity: .5; cursor: default; box-shadow: none; }
.preflight-pill { position: fixed; right: 24px; bottom: 96px; padding: 10px 14px; border-radius: 999px; background: rgba(16,16,16,.92); border: 1px solid rgba(255,255,255,.08); color: #e2e8f0; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; pointer-events: auto; }
.preflight-sidebar { position: fixed; top: 20px; right: 20px; width: 380px; max-width: calc(100vw - 40px); height: calc(100vh - 40px); border-radius: 28px; border: 1px solid rgba(255,255,255,.08); background: rgba(10,10,10,.96); backdrop-filter: blur(18px); color: #f8fafc; pointer-events: auto; overflow: hidden; transform: translateX(110%); transition: transform .28s ease; box-shadow: 0 28px 80px rgba(0,0,0,.45); }
.preflight-sidebar.open { transform: translateX(0); }
.preflight-sidebar-header { padding: 20px 20px 14px; border-bottom: 1px solid rgba(255,255,255,.06); }
.preflight-kicker { color: #00f2fe; font-size: 10px; letter-spacing: .22em; text-transform: uppercase; font-weight: 800; }
.preflight-title { margin-top: 10px; font-size: 24px; font-weight: 900; letter-spacing: .06em; text-transform: uppercase; }
.preflight-subtitle { margin-top: 8px; color: #94a3b8; font-size: 13px; line-height: 1.5; }
.preflight-section { padding: 18px 20px; border-bottom: 1px solid rgba(255,255,255,.05); }
.preflight-card { background: rgba(255,255,255,.03); border: 1px solid rgba(255,255,255,.06); border-left: 1px solid rgba(0,242,254,.22); border-radius: 18px; padding: 14px; }
.preflight-row { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
.preflight-label { color: #00f2fe; font-size: 10px; font-weight: 800; letter-spacing: .18em; text-transform: uppercase; }
.preflight-value { margin-top: 6px; color: #fff; font-size: 14px; line-height: 1.45; word-break: break-word; }
.preflight-muted { color: #94a3b8; font-size: 12px; line-height: 1.5; }
.preflight-list { display: flex; flex-direction: column; gap: 10px; margin-top: 14px; }
.preflight-step { display: flex; gap: 12px; align-items: flex-start; padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,.04); }
.preflight-step:last-child { border-bottom: 0; }
.preflight-dot { width: 12px; height: 12px; border-radius: 999px; margin-top: 4px; flex: 0 0 auto; background: rgba(148,163,184,.45); }
.preflight-dot.active { background: #00f2fe; box-shadow: 0 0 16px rgba(0,242,254,.45); }
.preflight-dot.done { background: #34d399; }
.preflight-dot.error { background: #f87171; }
.preflight-step-title { font-size: 13px; font-weight: 700; color: #fff; }
.preflight-step-detail { margin-top: 4px; font-size: 12px; color: #94a3b8; line-height: 1.45; }
.preflight-actions { display: flex; gap: 10px; flex-wrap: wrap; }
.preflight-btn { border: 0; border-radius: 14px; padding: 12px 16px; font-size: 11px; font-weight: 900; letter-spacing: .16em; text-transform: uppercase; cursor: pointer; }
.preflight-btn-primary { background: #00f2fe; color: #000; }
.preflight-btn-ghost { background: rgba(255,255,255,.06); color: #fff; border: 1px solid rgba(255,255,255,.08); }
.preflight-btn[disabled] { opacity: .5; cursor: default; }
.preflight-report-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,.55); display: none; align-items: center; justify-content: center; pointer-events: auto; }
.preflight-report-backdrop.open { display: flex; }
.preflight-report { width: min(760px, calc(100vw - 40px)); border-radius: 28px; background: rgba(10,10,10,.98); border: 1px solid rgba(255,255,255,.08); padding: 24px; color: #fff; box-shadow: 0 32px 90px rgba(0,0,0,.55); }
.preflight-badge { display: inline-flex; align-items: center; border-radius: 999px; padding: 6px 10px; font-size: 10px; text-transform: uppercase; letter-spacing: .16em; font-weight: 800; }
.preflight-safe { color: #86efac; background: rgba(34,197,94,.12); border: 1px solid rgba(34,197,94,.24); }
.preflight-warning { color: #fde68a; background: rgba(245,158,11,.12); border: 1px solid rgba(245,158,11,.24); }
.preflight-critical { color: #fca5a5; background: rgba(239,68,68,.12); border: 1px solid rgba(239,68,68,.24); }
.preflight-grid { display: grid; gap: 14px; grid-template-columns: repeat(2, minmax(0, 1fr)); margin-top: 18px; }
.preflight-report-card { background: rgba(255,255,255,.03); border: 1px solid rgba(255,255,255,.06); border-radius: 18px; padding: 16px; }
.preflight-report-card-title { color: #00f2fe; font-size: 10px; letter-spacing: .18em; text-transform: uppercase; font-weight: 800; }
.preflight-report-card-body { margin-top: 10px; color: #cbd5e1; font-size: 13px; line-height: 1.6; }
.preflight-report-actions { margin-top: 20px; display: flex; gap: 10px; flex-wrap: wrap; }
`;

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function riskClass(level?: string) {
  if (level === 'CRITICAL') return 'preflight-badge preflight-critical';
  if (level === 'WARNING') return 'preflight-badge preflight-warning';
  return 'preflight-badge preflight-safe';
}

export class PreflightOverlay {
  private handlers: OverlayHandlers;
  private root: ShadowRoot;
  private state: OverlayState;
  private site: SiteContext;

  constructor(site: SiteContext, handlers: OverlayHandlers) {
    this.site = site;
    this.handlers = handlers;
    const host = document.createElement('div');
    host.id = 'preflight-extension-root';
    document.documentElement.appendChild(host);
    this.root = host.attachShadow({ mode: 'open' });
    this.state = {
      activated: false,
      sidebarOpen: false,
      reportOpen: false,
      statusMessage: 'Activate PreFlight from the popup to intercept live DEX transactions.',
      timeline: [
        { label: 'Transaction intercepted', status: 'idle' },
        { label: 'Calldata decoded', status: 'idle' },
        { label: 'Off-chain verification', status: 'idle' },
        { label: 'On-chain checks', status: 'idle' },
        { label: 'Report ready', status: 'idle' },
      ],
      walletConnected: false,
      executionState: 'idle',
      mintState: 'idle',
    };
    this.render();
  }

  setActivated(activated: boolean) {
    this.state.activated = activated;
    this.state.statusMessage = activated
      ? 'PreFlight is active on this DEX page. The next transaction request will be intercepted before signature.'
      : 'Activate PreFlight from the popup to start intercepting live requests.';
    this.render();
  }

  setWalletConnected(connected: boolean, account?: string) {
    this.state.walletConnected = connected;
    if (connected && account) {
      this.state.statusMessage = `Wallet detected on page: ${account}`;
    }
    this.render();
  }

  setIntent(intent: NormalizedIntent) {
    this.state.intent = intent;
    this.state.sidebarOpen = true;
    this.state.reportOpen = false;
    this.state.report = undefined;
    this.state.mintState = 'idle';
    this.state.executionState = 'idle';
    this.state.statusMessage = `Captured ${intent.summary}. Review checks before execution.`;
    this.state.timeline = [
      { label: 'Transaction intercepted', status: 'done', detail: `${intent.method} captured from ${intent.protocol}` },
      { label: 'Calldata decoded', status: 'done', detail: intent.summary },
      { label: 'Off-chain verification', status: 'idle' },
      { label: 'On-chain checks', status: 'idle' },
      { label: 'Report ready', status: 'idle' },
    ];
    this.render();
  }

  setChecking(stageDetail: string) {
    this.state.sidebarOpen = true;
    this.state.timeline = [
      { label: 'Transaction intercepted', status: 'done', detail: this.state.intent?.method ?? 'Captured' },
      { label: 'Calldata decoded', status: 'done', detail: this.state.intent?.summary ?? 'Decoded intent' },
      { label: 'Off-chain verification', status: 'active', detail: stageDetail },
      { label: 'On-chain checks', status: 'idle' },
      { label: 'Report ready', status: 'idle' },
    ];
    this.state.statusMessage = 'Running PreFlight checks across off-chain and on-chain stages.';
    this.render();
  }

  setReport(report: CheckResult) {
    this.state.report = report;
    this.state.reportOpen = true;
    this.state.timeline = [
      { label: 'Transaction intercepted', status: 'done', detail: this.state.intent?.method ?? 'Captured' },
      { label: 'Calldata decoded', status: 'done', detail: this.state.intent?.summary ?? 'Decoded intent' },
      { label: 'Off-chain verification', status: 'done', detail: report.offchain.status },
      { label: 'On-chain checks', status: 'done', detail: report.onchain.status },
      { label: 'Report ready', status: 'done', detail: `${report.riskLevel} · score ${report.riskScore}` },
    ];
    this.state.statusMessage = 'Report ready. Mint the evidence entry and execute when you are comfortable.';
    this.render();
  }

  closeReport() {
    this.state.reportOpen = false;
    this.render();
  }

  setMintState(state: OverlayState['mintState']) {
    this.state.mintState = state;
    this.render();
  }

  setExecutionState(state: OverlayState['executionState'], message?: string) {
    this.state.executionState = state;
    if (message) this.state.statusMessage = message;
    this.render();
  }

  private bindEvents() {
    this.root.querySelector('[data-action="activate"]')?.addEventListener('click', () => this.handlers.onActivate());
    this.root.querySelector('[data-action="run-checks"]')?.addEventListener('click', () => this.handlers.onRunChecks());
    this.root.querySelector('[data-action="open-sidebar"]')?.addEventListener('click', () => {
      this.state.sidebarOpen = !this.state.sidebarOpen;
      this.render();
    });
    this.root.querySelector('[data-action="mint"]')?.addEventListener('click', () => this.handlers.onMint());
    this.root.querySelector('[data-action="execute"]')?.addEventListener('click', () => this.handlers.onExecute());
    this.root.querySelector('[data-action="dismiss-report"]')?.addEventListener('click', () => this.handlers.onDismissReport());
  }

  private render() {
    const report = this.state.report;
    const intent = this.state.intent;

    this.root.innerHTML = `
      <style>${BASE_STYLE}</style>
      <div class="preflight-shell">
        ${this.state.activated ? `<button class="preflight-fab" data-action="open-sidebar">PF</button>` : `<button class="preflight-fab" data-action="activate">Go</button>`}
        <div class="preflight-pill">${escapeHtml(this.state.statusMessage)}</div>

        <aside class="preflight-sidebar ${this.state.sidebarOpen ? 'open' : ''}">
          <div class="preflight-sidebar-header">
            <div class="preflight-kicker">${escapeHtml(this.site.protocol)} · ${escapeHtml(this.site.chainLabel)}</div>
            <div class="preflight-title">PreFlight</div>
            <div class="preflight-subtitle">Live verification layer for the official DEX page. Interception happens before wallet signature when activation is enabled.</div>
          </div>

          <div class="preflight-section">
            <div class="preflight-card">
              <div class="preflight-row">
                <div>
                  <div class="preflight-label">Activation</div>
                  <div class="preflight-value">${this.state.activated ? 'PreFlight active on this site' : 'Waiting for activation'}</div>
                  <div class="preflight-muted">${this.state.walletConnected ? 'Wallet detected on page context' : 'Wallet connection has not been observed yet'}</div>
                </div>
              </div>
              <div class="preflight-actions" style="margin-top:14px;">
                <button class="preflight-btn preflight-btn-primary" data-action="run-checks" ${!intent ? 'disabled' : ''}>Check PreFlight</button>
                <button class="preflight-btn preflight-btn-ghost" data-action="activate">${this.state.activated ? 'Re-activate' : 'Activate'}</button>
              </div>
            </div>
          </div>

          <div class="preflight-section">
            <div class="preflight-label">Captured intent</div>
            <div class="preflight-card" style="margin-top:12px;">
              <div class="preflight-value">${intent ? escapeHtml(intent.summary) : 'No transaction intent intercepted yet.'}</div>
              <div class="preflight-muted" style="margin-top:10px;">${intent ? `Method: ${escapeHtml(intent.method)} · Target: ${escapeHtml(intent.to)}` : 'Use the official DEX normally. Once activated, PreFlight will capture the next transaction request.'}</div>
            </div>
          </div>

          <div class="preflight-section">
            <div class="preflight-label">Check timeline</div>
            <div class="preflight-list">
              ${this.state.timeline.map((step) => `
                <div class="preflight-step">
                  <div class="preflight-dot ${step.status}"></div>
                  <div>
                    <div class="preflight-step-title">${escapeHtml(step.label)}</div>
                    ${step.detail ? `<div class="preflight-step-detail">${escapeHtml(step.detail)}</div>` : ''}
                  </div>
                </div>
              `).join('')}
            </div>
          </div>
        </aside>

        <div class="preflight-report-backdrop ${this.state.reportOpen ? 'open' : ''}">
          <div class="preflight-report">
            <div class="preflight-row">
              <div>
                <div class="preflight-kicker">Result view</div>
                <div class="preflight-title">Risk report</div>
                <div class="preflight-subtitle">Review the output before minting local evidence and re-submitting execution.</div>
              </div>
              <div class="${riskClass(report?.riskLevel)}">${escapeHtml(report?.riskLevel ?? 'SAFE')}</div>
            </div>

            <div class="preflight-grid">
              <div class="preflight-report-card">
                <div class="preflight-report-card-title">Summary</div>
                <div class="preflight-report-card-body">${escapeHtml(report ? `${report.riskLevel} · score ${report.riskScore}` : 'No report yet')}</div>
              </div>
              <div class="preflight-report-card">
                <div class="preflight-report-card-title">Intent</div>
                <div class="preflight-report-card-body">${escapeHtml(intent?.summary ?? 'No intent captured')}</div>
              </div>
              <div class="preflight-report-card">
                <div class="preflight-report-card-title">Off-chain</div>
                <div class="preflight-report-card-body">${escapeHtml(report ? report.offchain.details.join(' · ') : 'Pending')}</div>
              </div>
              <div class="preflight-report-card">
                <div class="preflight-report-card-title">On-chain</div>
                <div class="preflight-report-card-body">${escapeHtml(report ? report.onchain.details.join(' · ') : 'Pending')}</div>
              </div>
            </div>

            <div class="preflight-report-card" style="margin-top:14px;">
              <div class="preflight-report-card-title">Reasons</div>
              <div class="preflight-report-card-body">${escapeHtml(report ? report.reasons.join(' · ') : 'No reasons available')}</div>
            </div>

            <div class="preflight-report-actions">
              <button class="preflight-btn preflight-btn-primary" data-action="mint" ${!report ? 'disabled' : ''}>${this.state.mintState === 'pending' ? 'Minting...' : this.state.mintState === 'success' ? 'Evidence stored' : 'Mint Report NFT'}</button>
              <button class="preflight-btn preflight-btn-ghost" data-action="execute" ${!intent ? 'disabled' : ''}>${this.state.executionState === 'pending' ? 'Executing...' : this.state.executionState === 'success' ? 'Executed' : 'Execute transaction'}</button>
              <button class="preflight-btn preflight-btn-ghost" data-action="dismiss-report">Close</button>
            </div>
          </div>
        </div>
      </div>
    `;

    this.bindEvents();
  }
}
