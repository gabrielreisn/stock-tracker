import type { StockQuote } from '@/types/stocks';
import { dayKey, isB3Stock } from './stocks';

interface ChartResult {
  meta: { shortName?: string; longName?: string; regularMarketPrice?: number; regularMarketTime?: number; chartPreviousClose?: number };
  timestamp?: number[];
  indicators: { quote: { close: (number | null)[] }[]; adjclose?: { adjclose: (number | null)[] }[] };
  events?: { dividends?: Record<string, { date: number; amount: number }> };
}
export async function fetchStockQuote(ticker: string, signal: AbortSignal): Promise<StockQuote> {
  const symbol = isB3Stock(ticker) ? `${ticker}.SA` : ticker;
  const response = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=5y&interval=1d&events=div,split`, { signal, headers: { 'User-Agent': 'Mozilla/5.0' } });
  if (!response.ok) throw new Error('Market data unavailable');
  const data = await response.json() as { chart: { result: ChartResult[] | null } };
  const result = data.chart?.result?.[0];
  if (!result?.timestamp?.length) throw new Error('No price history');
  const closes = result.indicators.quote[0]?.close ?? [];
  const adjusted = result.indicators.adjclose?.[0]?.adjclose ?? closes;
  const days: number[] = [], prices: number[] = [];
  result.timestamp.forEach((time, index) => {
    const price = adjusted[index];
    if (typeof price === 'number' && Number.isFinite(price) && price > 0) { days.push(dayKey(new Date(time * 1000))); prices.push(price); }
  });
  if (!days.length) throw new Error('No price history');
  const validCloses = closes.filter((price): price is number => typeof price === 'number' && Number.isFinite(price) && price > 0);
  const dividends = Object.values(result.events?.dividends ?? {}).filter(d => Number.isFinite(d.amount) && d.amount > 0).map(d => ({ day: dayKey(new Date(d.date * 1000)), amount: d.amount }));
  const price = result.meta.regularMarketPrice;
  return {
    history: { days, prices, name: result.meta.longName ?? result.meta.shortName, dividends },
    price: typeof price === 'number' && price > 0 ? price : validCloses.at(-1),
    previousClose: validCloses.at(-2) ?? result.meta.chartPreviousClose,
    asOf: result.meta.regularMarketTime ? new Date(result.meta.regularMarketTime * 1000).toISOString() : undefined,
  };
}
