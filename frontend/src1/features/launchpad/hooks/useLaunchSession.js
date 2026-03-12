import { useEffect, useMemo, useState } from 'react';
import {
  DEX_SELECTION_STORAGE_KEY,
  LAUNCH_STORAGE_KEY,
  REPORT_STORAGE_KEY,
  SUPPORTED_DEXES,
  TOAST_TTL_MS,
} from '../../../shared/constants/app';
import { readJsonStorage, writeJsonStorage } from '../../../shared/utils/storage';

function createToast(title, message) {
  return {
    id: `toast_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    title,
    message,
  };
}

function findDexById(id) {
  return SUPPORTED_DEXES.find((dex) => dex.id === id) ?? null;
}

export function useLaunchSession() {
  const [isLaunched, setIsLaunched] = useState(() => Boolean(readJsonStorage(LAUNCH_STORAGE_KEY, false)));
  const [isDexSelectorOpen, setDexSelectorOpen] = useState(false);
  const [selectedDexId, setSelectedDexId] = useState(() => String(readJsonStorage(DEX_SELECTION_STORAGE_KEY, '') || ''));
  const [isSidebarOpen, setSidebarOpen] = useState(false);
  const [isResultOpen, setResultOpen] = useState(false);
  const [toasts, setToasts] = useState([]);
  const [mintedReports, setMintedReports] = useState(() => readJsonStorage(REPORT_STORAGE_KEY, []));

  const selectedDex = useMemo(() => findDexById(selectedDexId), [selectedDexId]);

  useEffect(() => {
    writeJsonStorage(LAUNCH_STORAGE_KEY, isLaunched);
  }, [isLaunched]);

  useEffect(() => {
    writeJsonStorage(DEX_SELECTION_STORAGE_KEY, selectedDexId);
  }, [selectedDexId]);

  useEffect(() => {
    const onStorage = (event) => {
      if (event.key === LAUNCH_STORAGE_KEY && event.newValue) {
        try {
          setIsLaunched(Boolean(JSON.parse(event.newValue)));
        } catch {
          // no-op
        }
      }

      if (event.key === DEX_SELECTION_STORAGE_KEY && event.newValue) {
        try {
          setSelectedDexId(String(JSON.parse(event.newValue) ?? ''));
        } catch {
          // no-op
        }
      }
    };

    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const launch = () => {
    setIsLaunched(true);
    setDexSelectorOpen(true);
  };

  const closeDexSelector = () => setDexSelectorOpen(false);

  const chooseDex = (dexId) => {
    setSelectedDexId(dexId);
    setDexSelectorOpen(false);
    setIsLaunched(true);
    setSidebarOpen(false);
    setResultOpen(false);
  };

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
    isDexSelectorOpen,
    selectedDex,
    isSidebarOpen,
    isResultOpen,
    toasts,
    mintedReports,
    reportCount,
    launch,
    chooseDex,
    closeDexSelector,
    setSidebarOpen,
    setResultOpen,
    pushToast,
    addMintedReport,
    clearReports,
  };
}
