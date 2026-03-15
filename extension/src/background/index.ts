import browser from 'webextension-polyfill';
import type { NormalizedIntent, SiteSession, StoredReport } from '../shared/types';
import { runChecks } from './apiClient';
import { addReport, getReports, getSiteSessions, setSiteSession } from './sessionStore';

browser.runtime.onMessage.addListener((message: any, sender: any) => {
  if (!message || typeof message !== 'object') return undefined;

  if (message.type === 'PF_SET_SITE_STATE') {
    const payload = message.payload as SiteSession;
    return setSiteSession(payload.host, { ...payload, tabId: sender.tab?.id, updatedAt: Date.now() });
  }

  if (message.type === 'PF_GET_SITE_STATE') {
    return getSiteSessions();
  }

  if (message.type === 'PF_GET_REPORTS') {
    return getReports();
  }

  if (message.type === 'PF_RUN_CHECKS') {
    return runChecks(message.payload as NormalizedIntent);
  }

  if (message.type === 'PF_STORE_REPORT') {
    const payload = message.payload as StoredReport;
    return addReport(payload);
  }

  return undefined;
});
