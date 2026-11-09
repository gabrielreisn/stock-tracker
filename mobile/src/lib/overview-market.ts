import { BENCHMARKS } from '@/lib/benchmarks';
import { dayAxis, priceOn, rateBenchmarkLevels, rebase, type OverviewMarket, type ReturnPoint } from '@/lib/overview';
import { dateFromDay, dayFromDate, fetchBondRates } from '@/lib/bonds';
import type { BenchmarkId, DayKey, PriceHistory } from '@/types';

/** Same public adjusted-close endpoint as macOS. No account identifiers or credentials. */
export async function fetchOverviewHistory(ticker: string, start: DayKey, signal: AbortSignal): Promise<PriceHistory> {
  const symbol = /\dF?$/.test(ticker) ? `${ticker.replace(/F$/, '')}.SA` : ticker;
  const period1 = Math.floor(dateFromDay(start).getTime() / 1000);
  const period2 = Math.floor(Date.now() / 1000) + 86400;
  const response = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?period1=${period1}&period2=${period2}&interval=1d&events=div,split`, { signal });
  if (!response.ok) throw new Error('Price history unavailable');
  const data = await response.json();
  const result = data.chart?.result?.[0];
  const times: number[] = result?.timestamp ?? [];
  const prices: unknown[] = result?.indicators?.adjclose?.[0]?.adjclose ?? result?.indicators?.quote?.[0]?.close ?? [];
  const history: PriceHistory = { days: [], prices: [], name: result?.meta?.longName ?? result?.meta?.shortName };
  times.forEach((time, index) => {
    const price = prices[index];
    if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0) return;
    history.days.push(dayFromDate(new Date(time * 1000)));
    history.prices.push(price);
  });
  if (!history.days.length) throw new Error('Empty price history');
  return history;
}
export interface OverviewPrices { market: OverviewMarket; benchmarks: Record<string, PriceHistory> }
export async function fetchOverviewMarket(tickers: string[], start: DayKey, signal: AbortSignal): Promise<OverviewPrices> {
  const symbols = [...new Set([...tickers, 'BRL=X', '^SP500TR', '^BVSP', 'IFIX.SA'])];
  const results = await Promise.allSettled([fetchBondRates(start, signal), ...symbols.map(symbol => fetchOverviewHistory(symbol, start, signal))]);
  const rates = results[0].status === 'fulfilled' ? results[0].value as OverviewMarket['rates'] : null;
  const histories: Record<string, PriceHistory> = {};
  results.slice(1).forEach((result, index) => { if (result.status === 'fulfilled') histories[symbols[index]] = result.value as PriceHistory; });
  return { market: { stocks: histories, fx: histories['BRL=X'], funds: {}, rates }, benchmarks: { sp500: histories['^SP500TR'], ibov: histories['^BVSP'], ifix: histories['IFIX.SA'] } };
}

export function benchmarkLines(prices: OverviewPrices, enabled: readonly BenchmarkId[], start: DayKey, day: DayKey, from: DayKey) {
  const axis = dayAxis(start, day);
  const selected = new Set(enabled);
  return BENCHMARKS.filter(benchmark => selected.has(benchmark.id)).flatMap(benchmark => {
    let history: ReturnPoint[];
    if (benchmark.isRate) {
      history = prices.market.rates ? rateBenchmarkLevels(axis, prices.market.rates, benchmark.id as 'cdi' | 'ipca' | 'ipcaPlus6') : [];
    } else {
      history = axis.flatMap(date => {
        const price = priceOn(prices.benchmarks[benchmark.id], date);
        const fx = benchmark.id === 'sp500' ? priceOn(prices.market.fx, date) : 1;
        return price !== undefined && fx !== undefined ? [{ day: date, value: price * fx }] : [];
      });
    }
    const points = rebase(history, from);
    return points.length ? [{ id: benchmark.id, label: benchmark.label, points, dashed: benchmark.isRate }] : [];
  });
}
