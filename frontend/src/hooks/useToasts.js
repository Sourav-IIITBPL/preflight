import { useCallback, useMemo, useState } from 'react';
import { TOAST_TTL_MS } from '../constants';

function createToast(title, message) {
  return {
    id: `toast_${Date.now()}_${Math.random().toString(16).slice(2)}`,
    title,
    message,
  };
}

export function useToasts() {
  const [items, setItems] = useState([]);

  const pushToast = useCallback((title, message = '') => {
    const next = createToast(title, message);
    setItems((prev) => [...prev, next]);

    window.setTimeout(() => {
      setItems((prev) => prev.filter((item) => item.id !== next.id));
    }, TOAST_TTL_MS);
  }, []);

  const api = useMemo(() => ({ items, pushToast }), [items, pushToast]);
  return api;
}
