import Storage from 'expo-sqlite/kv-store';
import { useEffect } from 'react';
import { createStore } from '@/lib/external-store';
import {
  fetchQuotaReport,
  mergeFundHistories,
  type FundHistories,
  type FundReportKind,
} from '@/lib/cvm-funds';
import type { FundHolding } from '@/types';

interface CachedReport {
  at: number;
  rows: FundHistories;
}
const CACHE_KEY = 'cvm-fund-quotes-v1';
function loadCache(): Record<string, CachedReport> {
  try {
    return JSON.parse(Storage.getItemSync(CACHE_KEY) ?? '{}');
  } catch {
    return {};
  }
}
const cache = loadCache();
const store = createStore({
  histories: mergeFundHistories(
    ...Object.values(cache).map((entry) => entry.rows),
  ),
  loading: false,
  done: 0,
  total: 0,
  failed: [] as string[],
});
let pending: Promise<void> | undefined;

type FundIdentifier = Pick<FundHolding, 'kind' | 'cnpj'>;

function reportsFor(holdings: FundIdentifier[], now: Date) {
  const reports: {
    kind: FundReportKind;
    month: number;
    ids: Set<string>;
    key: string;
  }[] = [];
  for (let offset = 0; offset < 16; offset++) {
    const date = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const month = date.getFullYear() * 100 + date.getMonth() + 1;
    for (const kind of ['fif', 'fidc'] as const) {
      const ids = new Set(
        holdings.filter((fund) => fund.kind === kind).map((fund) => fund.cnpj),
      );
      if (ids.size)
        reports.push({
          kind,
          month,
          ids,
          key: `${kind}:${month}:${[...ids].sort().join(',')}`,
        });
    }
  }
  return reports;
}

export function refreshFundMarket(
  holdings: FundIdentifier[],
  force = false,
): Promise<void> {
  // Serialize refreshes so an explicit pull is never swallowed by an in-flight initial load.
  if (pending) return pending.then(() => refreshFundMarket(holdings, force));
  const reports = reportsFor(holdings, new Date());
  store.set({
    loading: reports.length > 0,
    done: 0,
    total: reports.length,
    failed: [],
  });
  pending = (async function loadFundReports() {
    const failed: string[] = [];
    const loaded: FundHistories[] = [];
    // Bound memory: download/inflate one archive, keeping only held funds' numeric rows.
    for (const [index, report] of reports.entries()) {
      const saved = cache[report.key];
      let rows = saved?.rows;
      if (force || !saved || Date.now() - saved.at > 12 * 60 * 60 * 1000) {
        try {
          rows = await fetchQuotaReport(report.kind, report.month, report.ids);
          cache[report.key] = { at: Date.now(), rows };
        } catch {
          failed.push(`${report.kind.toUpperCase()} ${report.month}`);
        }
      }
      if (rows) loaded.push(rows);
      store.set({
        histories: mergeFundHistories(store.get().histories, ...loaded),
        done: index + 1,
      });
    }
    // Persist compact prices, never whole ZIPs. Limit obsolete holding/report combinations.
    const keep = Object.entries(cache)
      .sort((a, b) => b[1].at - a[1].at)
      .slice(0, 96);
    try {
      Storage.setItemSync(CACHE_KEY, JSON.stringify(Object.fromEntries(keep)));
    } catch {
      /* In-memory quotes still work if storage is full. */
    }
    store.set({ failed });
  })().finally(() => {
    store.set({ loading: false });
    pending = undefined;
  });
  return pending;
}

export function useFundMarket(holdings: FundHolding[]) {
  const state = store.useValue();
  // Only membership/type changes reload reports; editing quantity doesn't redownload prices.
  const signature = [
    ...new Set(holdings.map((fund) => `${fund.kind}:${fund.cnpj}`)),
  ]
    .sort()
    .join(',');
  useEffect(
    function loadFundPrices() {
      const funds = signature
        ? signature.split(',').map((entry) => {
            const [kind, cnpj] = entry.split(':');
            return { kind, cnpj } as FundIdentifier;
          })
        : [];
      void refreshFundMarket(funds);
    },
    [signature],
  );
  return state;
}
