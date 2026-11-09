import { useEffect } from 'react';
import { fetchBondRates, type BondRates } from '@/lib/bonds';
import { createStore } from '@/lib/external-store';
import { fetchStockQuote } from '@/lib/stock-market';
import { rangeStart } from '@/lib/stocks';
import type { StockQuote } from '@/types/stocks';

const store = createStore({ quotes: {} as Record<string, StockQuote>, rates: null as BondRates | null, loading: false, failed: [] as string[], fetchedAt: undefined as string | undefined });
let pending: Promise<void> | undefined;
export function refreshStockMarket(tickers: string[]): Promise<void> {
  if (pending) return pending.then(() => refreshStockMarket(tickers));
  store.set({ loading: true });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  const symbols = [...new Set([...tickers, 'BRL=X', '^SP500TR', '^BVSP'])];
  pending = (async () => {
    const results = await Promise.allSettled([
      ...symbols.map(async symbol => ({ symbol, quote: await fetchStockQuote(symbol, controller.signal) })),
    ]);
    const quotes = { ...store.get().quotes }, failed: string[] = [];
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') quotes[result.value.symbol] = result.value.quote;
      else failed.push(symbols[index]);
    });
    let rates = store.get().rates;
    try { rates = await fetchBondRates(rangeStart('5Y'), controller.signal); }
    catch { failed.push('CDI / IPCA'); }
    store.set({ quotes, rates, failed, fetchedAt: new Date().toISOString(), loading: false });
  })().finally(() => { clearTimeout(timeout); pending = undefined; });
  return pending;
}
export function useStockMarket(tickers: string[]) {
  const state = store.useValue();
  const symbols = tickers.join(',');
  useEffect(function loadStockPrices() {
    void refreshStockMarket(symbols ? symbols.split(',') : []);
  }, [symbols]);
  return state;
}
