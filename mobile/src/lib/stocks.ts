import type { PriceHistory, Trade } from '@/types';
import type { StockHolding, StockPoint, StockQuote, StockRange, StockSort } from '@/types/stocks';

export const isB3Stock = (ticker: string) => /^[A-Z]{4}[0-9]{1,2}F?$/.test(ticker);
export const stockCurrency = (ticker: string) => isB3Stock(ticker) ? 'BRL' : 'USD';
export function stockNumber(input: string): number | undefined {
  let value = input.trim();
  if (value.includes(',')) value = value.replaceAll('.', '').replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(value)) return undefined;
  const result = Number(value);
  return Number.isFinite(result) && result > 0 ? result : undefined;
}
export function stockHoldings(trades: Trade[]): StockHolding[] {
  const groups = new Map<string, Trade[]>();
  for (const trade of [...trades].sort((a, b) => a.date.localeCompare(b.date))) {
    groups.set(trade.ticker, [...(groups.get(trade.ticker) ?? []), trade]);
  }
  return [...groups].flatMap(([ticker, rows]) => {
    const quantity = rows.reduce((q, trade) => Math.max(0, q + (trade.kind === 'buy' ? trade.quantity : -trade.quantity)), 0);
    const buys = rows.filter(trade => trade.kind === 'buy' && trade.price !== undefined);
    const shares = buys.reduce((q, trade) => q + trade.quantity, 0);
    const averagePrice = shares > 0 ? buys.reduce((cost, trade) => cost + trade.quantity * trade.price!, 0) / shares : undefined;
    return quantity > 0.000001 ? [{ ticker, quantity, averagePrice }] : [];
  });
}
export function replaceStock(trades: Trade[], ticker: string, quantity: number, price?: number): Trade[] {
  const first = trades.find(trade => trade.ticker === ticker);
  return [...trades.filter(trade => trade.ticker !== ticker), {
    id: first?.id ?? `demo-stock-${ticker}-${Date.now()}`, ticker, kind: 'buy' as const,
    date: first?.date ?? new Date().toISOString(), quantity, ...(price === undefined ? {} : { price }),
  }].sort((a, b) => a.date.localeCompare(b.date));
}
export function addStock(trades: Trade[], ticker: string, quantity: number, price?: number) {
  const held = stockHoldings(trades).find(row => row.ticker === ticker);
  const average = held?.averagePrice !== undefined && price !== undefined
    ? (held.quantity * held.averagePrice + quantity * price) / (held.quantity + quantity)
    : held?.averagePrice ?? price;
  return replaceStock(trades, ticker, (held?.quantity ?? 0) + quantity, average);
}
export function closeBefore(history: PriceHistory | undefined, day: number): number | undefined {
  if (!history) return undefined;
  let lo = 0, hi = history.days.length;
  while (lo < hi) { const mid = (lo + hi) >>> 1; if (history.days[mid] <= day) lo = mid + 1; else hi = mid; }
  return lo > 0 ? history.prices[lo - 1] : undefined;
}
export function dayKey(date: Date) { return date.getUTCFullYear() * 10000 + (date.getUTCMonth() + 1) * 100 + date.getUTCDate(); }
export function rangeStart(range: StockRange, now = new Date()) {
  const date = new Date(now);
  if (range === 'YTD') return date.getUTCFullYear() * 10000 + 101;
  if (range.endsWith('Y')) date.setUTCFullYear(date.getUTCFullYear() - Number(range.slice(0, -1)));
  else date.setUTCMonth(date.getUTCMonth() - Number(range.slice(0, -1)));
  return dayKey(date);
}
export function inReais(ticker: string, quote: StockQuote | undefined, dollar: StockQuote | undefined): PriceHistory | undefined {
  if (!quote) return undefined;
  if (isB3Stock(ticker)) return quote.history;
  const days: number[] = [], prices: number[] = [];
  quote.history.days.forEach((day, index) => {
    const rate = closeBefore(dollar?.history, day);
    if (rate !== undefined) { days.push(day); prices.push(quote.history.prices[index] * rate); }
  });
  return days.length ? { days, prices } : undefined;
}
/** Today's quantities, chain-linked at previous-close weights, like the desktop. */
export function portfolioIndex(holdings: StockHolding[], quotes: Record<string, StockQuote>, start: number): StockPoint[] {
  const rows = holdings.map(h => ({ ...h, history: inReais(h.ticker, quotes[h.ticker], quotes['BRL=X']) }));
  if (!rows.length || rows.some(row => !row.history)) return [];
  const axis = [...new Set(rows.flatMap(row => row.history!.days))].sort((a, b) => a - b);
  const first = axis.findIndex(day => day >= start);
  if (first < 0) return [];
  const days = axis.slice(Math.max(0, first - 1));
  let value = 1;
  return days.map((day, index) => {
    if (index > 0) {
      let before = 0, after = 0;
      for (const row of rows) {
        const p0 = closeBefore(row.history, days[index - 1]), p1 = closeBefore(row.history, day);
        if (p0 !== undefined && p1 !== undefined) { before += row.quantity * p0; after += row.quantity * p1; }
      }
      if (before > 0) value *= after / before;
    }
    return { day, value: value - 1 };
  });
}
export function holdingMetrics(h: StockHolding, quotes: Record<string, StockQuote>) {
  const quote = quotes[h.ticker], price = quote?.price;
  const fx = isB3Stock(h.ticker) ? 1 : quotes['BRL=X']?.price;
  const value = price !== undefined && fx !== undefined ? h.quantity * price * fx : undefined;
  const gain = price !== undefined && h.averagePrice ? price / h.averagePrice - 1 : undefined;
  const today = price !== undefined && quote.previousClose ? price / quote.previousClose - 1 : undefined;
  const base = closeBefore(quote?.history, new Date().getFullYear() * 10000 + 100);
  const ytd = price !== undefined && base ? price / base - 1 : undefined;
  return { price, value, gain, today, ytd };
}
export function sortStocks(rows: StockHolding[], quotes: Record<string, StockQuote>, sort: StockSort, ascending: boolean) {
  return [...rows].sort((a, b) => {
    if (sort === 'ticker') return a.ticker.localeCompare(b.ticker) * (ascending ? 1 : -1);
    const metric = (h: StockHolding) => sort === 'shares' ? h.quantity : sort === 'average' ? h.averagePrice : holdingMetrics(h, quotes)[sort];
    const x = metric(a), y = metric(b);
    if (x === undefined || y === undefined) return x === y ? a.ticker.localeCompare(b.ticker) : x === undefined ? 1 : -1;
    return (x - y) * (ascending ? 1 : -1) || a.ticker.localeCompare(b.ticker);
  });
}
