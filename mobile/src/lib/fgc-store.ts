import { useEffect, useState } from 'react';

import { fetchConglomerates } from '@/lib/fgc';
import type { Conglomerates } from '@/types';

// Public data only. Keep it for 30 days in this session, as on desktop.
let cached: { groups: Conglomerates; loadedAt: number } | null = null;
const emptyGroups: Conglomerates = {};
export function useConglomerates() {
  const [result, setResult] = useState<{ attempt: number; groups: Conglomerates | null; failed: boolean } | null>(null);
  const [request, setRequest] = useState(() => ({ attempt: 0, at: Date.now() }));
  const { attempt, at } = request;
  useEffect(function loadPublicConglomerates() {
    if (cached && at - cached.loadedAt < 30 * 86400000) return;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    let active = true;
    fetchConglomerates(controller.signal).then(groups => {
      if (!active) return;
      cached = { groups, loadedAt: Date.now() };
      setResult({ attempt, groups, failed: false });
    }).catch(() => { if (active) setResult({ attempt, groups: null, failed: true }); })
      .finally(() => clearTimeout(timeout));
    return () => { active = false; controller.abort(); clearTimeout(timeout); };
  }, [attempt, at]);
  const current = result?.attempt === attempt ? result : null;
  const fresh = cached && at - cached.loadedAt < 30 * 86400000;
  return {
    groups: cached?.groups ?? current?.groups ?? emptyGroups,
    loading: !fresh && !current,
    failed: current?.failed ?? false,
    retry: () => setRequest(value => ({ attempt: value.attempt + 1, at: Date.now() })),
  };
}
