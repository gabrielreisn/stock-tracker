import { useEffect, useState } from 'react';

import { createDemoData } from '@/data/demo';
import { fetchBondRates, type BondRates } from '@/lib/bonds';
import { createStore } from '@/lib/external-store';
import type { Bond } from '@/types';

// Session-only demo edits, deliberately separate from Pluggy and personal storage.
const store = createStore({ bonds: createDemoData().bonds });
export const useBonds = () => store.useValue().bonds;
export function saveBond(bond: Bond) {
  const current = store.get().bonds;
  store.set({ bonds: current.some(b => b.id === bond.id) ? current.map(b => b.id === bond.id ? bond : b) : [...current, bond] });
}
export function deleteBond(id: string) { store.set({ bonds: store.get().bonds.filter(b => b.id !== id) }); }
let cached: { start: number; rates: BondRates } | null = null;
interface RateResult { start: number; attempt: number; rates: BondRates | null; failed: boolean }
export function useBondRates(start: number) {
  const [result, setResult] = useState<RateResult | null>(null);
  const [attempt, setAttempt] = useState(0);
  useEffect(function loadPublicBondRates() {
    if (cached && cached.start <= start) return;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    let active = true;
    fetchBondRates(start, controller.signal).then(rates => {
      if (!active) return;
      cached = { start, rates };
      setResult({ start, attempt, rates, failed: false });
    }).catch(() => {
      if (active) setResult({ start, attempt, rates: null, failed: true });
    }).finally(() => clearTimeout(timeout));
    return () => { active = false; controller.abort(); clearTimeout(timeout); };
  }, [start, attempt]);
  const current = result?.start === start && result.attempt === attempt ? result : null;
  const rates = cached && cached.start <= start ? cached.rates : current?.rates ?? null;
  return { rates, loading: !rates && !current, failed: !rates && (current?.failed ?? false), retry: () => { cached = null; setAttempt(value => value + 1); } };
}
