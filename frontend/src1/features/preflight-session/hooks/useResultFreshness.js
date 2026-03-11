import { useEffect, useMemo, useRef, useState } from 'react';

export function useResultFreshness({ isOpen, openedAtMs, ttlMs, onStale }) {
  const [nowMs, setNowMs] = useState(0);
  const staleTriggeredRef = useRef(false);

  useEffect(() => {
    if (!isOpen) {
      staleTriggeredRef.current = false;
      return;
    }

    const timer = setInterval(() => {
      setNowMs(Date.now());
    }, 500);

    return () => clearInterval(timer);
  }, [isOpen]);

  const elapsedMs = useMemo(() => {
    if (!isOpen || !openedAtMs) return 0;
    return Math.max(0, nowMs - openedAtMs);
  }, [isOpen, openedAtMs, nowMs]);

  useEffect(() => {
    if (!isOpen) return;

    if (elapsedMs >= ttlMs && !staleTriggeredRef.current) {
      staleTriggeredRef.current = true;
      onStale?.();
    }
  }, [elapsedMs, isOpen, ttlMs, onStale]);

  const secondsLeft = useMemo(() => Math.max(0, Math.ceil((ttlMs - elapsedMs) / 1000)), [ttlMs, elapsedMs]);

  return {
    elapsedMs,
    secondsLeft,
    isStale: elapsedMs >= ttlMs,
  };
}
