import { useEffect, useMemo, useState } from 'react';
import { LAUNCH_STORAGE_KEY, REPORT_STORAGE_KEY, TOAST_TTL_MS } from '../../../shared/constants/app';
import { readJsonStorage, writeJsonStorage } from '../../../shared/utils/storage';

function createToast(title, message) {
  return {
    id: `toast_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    title,
    message,
  };
}

export function useLaunchSession() {
  const [isLaunched, setIsLaunched] = useState(() => Boolean(readJsonStorage(LAUNCH_STORAGE_KEY, false)));
  const [isSidebarOpen, setSidebarOpen] = useState(false);
  const [isResultOpen, setResultOpen] = useState(false);
  const [toasts, setToasts] = useState([]);
  const [mintedReports, setMintedReports] = useState(() => readJsonStorage(REPORT_STORAGE_KEY, []));

  useEffect(() => {
    writeJsonStorage(LAUNCH_STORAGE_KEY, isLaunched);
  }, [isLaunched]);

  useEffect(() => {
    const onStorage = (event) => {
      if (event.key !== LAUNCH_STORAGE_KEY || !event.newValue) return;
      try {
        setIsLaunched(Boolean(JSON.parse(event.newValue)));
      } catch {
        // no-op
      }
    };

    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const launch = () => setIsLaunched(true);

  const pushToast = (title, message = '') => {
    const next = createToast(title, message);
    setToasts((prev) => [...prev, next]);

    setTimeout(() => {
      setToasts((prev) => prev.filter((item) => item.id !== next.id));
    }, TOAST_TTL_MS);
  };

  const addMintedReport = (report) => {
    setMintedReports((prev) => {
      const next = [report, ...prev];
      writeJsonStorage(REPORT_STORAGE_KEY, next);
      return next;
    });
  };

  const clearReports = () => {
    setMintedReports([]);
    writeJsonStorage(REPORT_STORAGE_KEY, []);
  };

  const reportCount = useMemo(() => mintedReports.length, [mintedReports.length]);

  return {
    isLaunched,
    isSidebarOpen,
    isResultOpen,
    toasts,
    mintedReports,
    reportCount,
    launch,
    setSidebarOpen,
    setResultOpen,
    pushToast,
    addMintedReport,
    clearReports,
  };
}
