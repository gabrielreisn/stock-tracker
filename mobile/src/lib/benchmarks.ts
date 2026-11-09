import Storage from 'expo-sqlite/kv-store';

import { createStore } from '@/lib/external-store';
import type { StringKey } from '@/lib/i18n';

import type { BenchmarkId } from '@/types';
export type { BenchmarkId } from '@/types';

type Benchmark = {
  id: BenchmarkId;
  label: string;
  detail: StringKey;
  /** Rate-based benchmarks are drawn dashed, a second cue besides color. */
  isRate: boolean;
};

/** Same list and order as `BenchmarkID` on macOS, so colors never move. */
export const BENCHMARKS: readonly Benchmark[] = [
  {
    id: 'cdi',
    label: 'CDI',
    detail: 'Interbank deposit rate, the usual fixed-income yardstick. Banco Central, series 12.',
    isRate: true,
  },
  {
    id: 'ipca',
    label: 'IPCA',
    detail: 'Official inflation. IBGE, via Banco Central series 433.',
    isRate: true,
  },
  {
    id: 'sp500',
    label: 'S&P 500',
    detail: 'S&P 500 with dividends reinvested (^SP500TR), converted to reais at USD/BRL.',
    isRate: false,
  },
  {
    id: 'ipcaPlus6',
    label: 'IPCA+6%',
    detail: 'Inflation plus a 6% real return a year — a typical long-term target.',
    isRate: true,
  },
  {
    id: 'ifix',
    label: 'IFIX',
    detail: "B3's real-estate fund (FII) index, with distributions reinvested. Starts Dec 2010.",
    isRate: false,
  },
  {
    id: 'ibov',
    label: 'IBOV',
    detail: "Ibovespa, B3's main stock index (a total-return index), via Yahoo (^BVSP).",
    isRate: false,
  },
];

/** More lines than this can't all be told apart by color, so the chart caps them. */
export const MAX_BENCHMARKS = 3;

const STORAGE_KEY = 'benchmarks';
const DEFAULT_BENCHMARKS: readonly BenchmarkId[] = ['cdi', 'ipca'];

function inOrder(ids: readonly BenchmarkId[]): BenchmarkId[] {
  return BENCHMARKS.map((benchmark) => benchmark.id).filter((id) => ids.includes(id));
}

function load(): BenchmarkId[] {
  try {
    const saved: unknown = JSON.parse(Storage.getItemSync(STORAGE_KEY) ?? 'null');
    if (Array.isArray(saved)) return inOrder(saved).slice(0, MAX_BENCHMARKS);
  } catch {
    // An unreadable preference falls back to the default below.
  }
  return [...DEFAULT_BENCHMARKS];
}

const store = createStore({ enabled: load() });

export function useEnabledBenchmarks() {
  return store.useValue().enabled;
}

export function setBenchmark(id: BenchmarkId, isEnabled: boolean) {
  const current = store.get().enabled;
  if (isEnabled && !current.includes(id) && current.length >= MAX_BENCHMARKS) return;
  const enabled = inOrder(isEnabled ? [...current, id] : current.filter((other) => other !== id));
  store.set({ enabled });
  Storage.setItemSync(STORAGE_KEY, JSON.stringify(enabled));
}
