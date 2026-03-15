import browser from 'webextension-polyfill';
import type { SiteSession, StoredReport } from '../shared/types';

const SITE_SESSIONS_KEY = 'preflight.siteSessions.v1';
const REPORTS_KEY = 'preflight.extensionReports.v1';

async function readObject<T>(key: string, fallback: T): Promise<T> {
  const result = await browser.storage.local.get(key);
  return (result[key] as T | undefined) ?? fallback;
}

export async function getSiteSessions(): Promise<Record<string, SiteSession>> {
  return readObject<Record<string, SiteSession>>(SITE_SESSIONS_KEY, {});
}

export async function setSiteSession(host: string, session: SiteSession): Promise<void> {
  const current = await getSiteSessions();
  current[host] = session;
  await browser.storage.local.set({ [SITE_SESSIONS_KEY]: current });
}

export async function getReports(): Promise<StoredReport[]> {
  return readObject<StoredReport[]>(REPORTS_KEY, []);
}

export async function addReport(report: StoredReport): Promise<StoredReport[]> {
  const current = await getReports();
  const next = [report, ...current].slice(0, 50);
  await browser.storage.local.set({ [REPORTS_KEY]: next });
  return next;
}
