import { useEffect } from "react";
import { fetchBondRates, type BondRates } from "@/lib/bonds";
import { createStore } from "@/lib/external-store";
import { fetchB3Dividends } from "@/lib/stock-dividends";
import type { StockDividend, StockQuote } from "@/types/stocks";
import { fetchStockQuote } from "@/lib/stock-market";
import { rangeStart } from "@/lib/stocks";

const store = createStore({
  quotes: {} as Record<string, StockQuote>,
  rates: null as BondRates | null,
  announcements: {} as Record<string, StockDividend[] | null>,
  dividendFailures: [] as string[],
  loading: false,
  failed: [] as string[],
  fetchedAt: undefined as string | undefined,
});
let pending: Promise<void> | undefined;
export function refreshStockMarket(tickers: string[]): Promise<void> {
  if (pending) return pending.then(() => refreshStockMarket(tickers));
  store.set({ loading: true });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  const symbols = [...new Set([...tickers, "BRL=X", "^SP500TR", "^BVSP"])];
  pending = (async () => {
    const dividendRequest = Promise.allSettled(
      tickers.map(async (ticker) => ({
        ticker,
        rows: await fetchB3Dividends(ticker, controller.signal),
      })),
    );
    const rateRequest = fetchBondRates(
      rangeStart("5Y"),
      controller.signal,
    ).catch(() => null);
    const results = await Promise.allSettled([
      ...symbols.map(async (symbol) => ({
        symbol,
        quote: await fetchStockQuote(symbol, controller.signal),
      })),
    ]);
    const quotes = { ...store.get().quotes },
      failed: string[] = [];
    results.forEach((result, index) => {
      if (result.status === "fulfilled")
        quotes[result.value.symbol] = result.value.quote;
      else failed.push(symbols[index]);
    });
    const announcements = { ...store.get().announcements },
      dividendFailures: string[] = [];
    const dividends = await dividendRequest;
    dividends.forEach((result, index) => {
      if (result.status === "fulfilled")
        announcements[result.value.ticker] = result.value.rows;
      else dividendFailures.push(tickers[index]);
    });
    const rates = await rateRequest;
    if (!rates) failed.push("CDI / IPCA");
    store.set({
      quotes,
      rates: rates ?? store.get().rates,
      announcements,
      dividendFailures,
      failed,
      fetchedAt: new Date().toISOString(),
      loading: false,
    });
  })().finally(() => {
    clearTimeout(timeout);
    pending = undefined;
  });
  return pending;
}
export function useStockMarket(tickers: string[]) {
  const state = store.useValue();
  const symbols = tickers.join(",");
  useEffect(
    function loadStockPrices() {
      void refreshStockMarket(symbols ? symbols.split(",") : []);
    },
    [symbols],
  );
  return state;
}
