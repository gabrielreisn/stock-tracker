import { businessDays, dateFromDay, dayFromDate, describeRate, valueBond, type BondRates } from '@/lib/bonds';
import type { Bond, DayKey, FundHolding, PriceHistory, Trade } from '@/types';

export const ASSET_CLASSES = ['stocks', 'bonds', 'funds'] as const;
export type AssetClass = typeof ASSET_CLASSES[number];
export const ASSET_COLORS = { stocks: '#2a78d6', bonds: '#1baf7a', funds: '#eb6834', us: '#7e4fd6' };
export const RANGES = ['3M', 'YTD', '1Y', '3Y', '5Y', 'All'] as const;
export type OverviewRange = typeof RANGES[number];
export interface Position { id: string; name: string; detail: string; assetClass: AssetClass; value?: number; us?: boolean }
export interface ValueSeries { assetClass: AssetClass; values: (number | undefined)[] }
export interface ReturnPoint { day: DayKey; value: number }
export interface OverviewMarket { stocks: Record<string, PriceHistory>; funds: Record<string, PriceHistory>; fx?: PriceHistory; rates: BondRates | null }
export const emptyMarket: OverviewMarket = { stocks: {}, funds: {}, rates: null };
export const isUS = (ticker: string) => !/\dF?$/.test(ticker);
export function priceOn(history: PriceHistory | undefined, day: DayKey): number | undefined {
  if (!history) return undefined;
  let low = 0, high = history.days.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (history.days[mid] <= day) low = mid + 1;
    else high = mid - 1;
  }
  return high >= 0 ? history.prices[high] : undefined;
}
export function stockQuantities(trades: Trade[]) {
  const quantities: Record<string, number> = {};
  for (const trade of trades) quantities[trade.ticker] = (quantities[trade.ticker] ?? 0) + (trade.kind === 'buy' ? 1 : -1) * trade.quantity;
  return Object.entries(quantities).filter(([, quantity]) => quantity > 0);
}
export function rangeStart(range: OverviewRange, day: DayKey, first: DayKey): DayKey {
  const date = dateFromDay(day);
  if (range === 'All') return first;
  if (range === 'YTD') return date.getUTCFullYear() * 10000 + 101;
  const months = { '3M': 3, '1Y': 12, '3Y': 36, '5Y': 60 }[range];
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() - months, 1));
  const end = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  return dayFromDate(new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), Math.min(date.getUTCDate(), end))));
}
export function dayAxis(start: DayKey, end: DayKey) {
  const days: DayKey[] = [];
  for (let time = dateFromDay(start).getTime(); time <= dateFromDay(end).getTime(); time += 86400000) {
    const day = dayFromDate(new Date(time));
    const next = dayFromDate(new Date(time + 86400000));
    if (businessDays(day, next)) days.push(day);
  }
  return days;
}
/** Today's holdings, with each day's return weighted by yesterday's value. Missing histories never become zero prices. */
export function chainReturns(days: DayKey[], series: ValueSeries[]): ReturnPoint[] {
  let index = 1;
  let hasHistory = false;
  const result: ReturnPoint[] = [];
  for (let i = 1; i < days.length; i++) {
    let before = 0, after = 0;
    for (const item of series) {
      const a = item.values[i - 1], b = item.values[i];
      if (a !== undefined && b !== undefined && a > 0) { before += a; after += b; }
    }
    if (before > 0) {
      if (!hasHistory) result.push({ day: days[i - 1], value: 1 });
      hasHistory = true;
      index *= after / before;
    }
    if (hasHistory) result.push({ day: days[i], value: index });
  }
  return result;
}
export function rebase(points: ReturnPoint[], start: DayKey): ReturnPoint[] {
  const base = points.filter(point => point.day < start).at(-1) ?? points.find(point => point.day >= start);
  if (!base || base.value <= 0) return [];
  return points.filter(point => point.day >= start).map(point => ({ day: point.day, value: point.value / base.value - 1 }));
}
export function buildOverview(trades: Trade[], bonds: Bond[], funds: FundHolding[], market: OverviewMarket, day: DayKey) {
  const quantities = stockQuantities(trades);
  const starts = [...trades.map(trade => Number(trade.date.slice(0, 10).replaceAll('-', ''))), ...bonds.map(bond => bond.issueDay), ...Object.values(market.funds).flatMap(history => history.days.slice(0, 1))];
  const first = Math.min(rangeStart('5Y', day, day), ...starts);
  const axis = dayAxis(dayFromDate(new Date(dateFromDay(first).getTime() - 31 * 86400000)), day);
  const positions: Position[] = [];
  const series: ValueSeries[] = [];
  for (const [ticker, quantity] of quantities) {
    const history = market.stocks[ticker];
    const valueAt = (date: DayKey) => {
      const price = priceOn(history, date), fx = isUS(ticker) ? priceOn(market.fx, date) : 1;
      return price !== undefined && fx !== undefined ? price * fx * quantity : undefined;
    };
    positions.push({ id: `stock-${ticker}`, name: ticker, detail: history?.name ?? `${quantity}`, assetClass: 'stocks', value: valueAt(day), us: isUS(ticker) });
    series.push({ assetClass: 'stocks', values: axis.map(valueAt) });
  }
  for (const bond of bonds) {
    positions.push({ id: bond.id, name: `${bond.kind} ${bond.issuer}`, detail: `${describeRate(bond)} · ${bond.code}`, assetClass: 'bonds', value: valueBond(bond, market.rates, day)?.gross });
    series.push({ assetClass: 'bonds', values: axis.map(date => date <= bond.maturityDay ? valueBond(bond, market.rates, date)?.gross : undefined) });
  }
  for (const fund of funds) {
    const history = market.funds[fund.cnpj];
    const price = priceOn(history, day) ?? (fund.statementDay && fund.statementDay <= day ? fund.statementPrice : undefined);
    positions.push({ id: fund.id, name: fund.name, detail: fund.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5'), assetClass: 'funds', value: price === undefined ? undefined : fund.quantity * price });
    if (history) series.push({ assetClass: 'funds', values: axis.map(date => { const price = priceOn(history, date); return price === undefined ? undefined : price * fund.quantity; }) });
  }
  positions.sort((a, b) => (b.value ?? -1) - (a.value ?? -1) || a.name.localeCompare(b.name));
  const values = Object.fromEntries(ASSET_CLASSES.map(assetClass => [assetClass, positions.filter(position => position.assetClass === assetClass).reduce((sum, position) => sum + (position.value ?? 0), 0)])) as Record<AssetClass, number>;
  const missing = positions.filter(position => position.value === undefined).length;
  const total = Object.values(values).reduce((sum, value) => sum + value, 0);
  const slices = [
    { label: 'Stocks B3' as const, color: ASSET_COLORS.stocks, value: positions.filter(position => position.assetClass === 'stocks' && !position.us).reduce((sum, position) => sum + (position.value ?? 0), 0) },
    { label: 'Stocks US' as const, color: ASSET_COLORS.us, value: positions.filter(position => position.us).reduce((sum, position) => sum + (position.value ?? 0), 0) },
    { label: 'Bonds' as const, color: ASSET_COLORS.bonds, value: values.bonds },
    { label: 'Funds' as const, color: ASSET_COLORS.funds, value: values.funds },
  ].filter(slice => slice.value > 0);
  const curves = Object.fromEntries(ASSET_CLASSES.map(assetClass => [assetClass, chainReturns(axis, series.filter(item => item.assetClass === assetClass))])) as Record<AssetClass, ReturnPoint[]>;
  return { positions, values, total, missing, slices, curve: chainReturns(axis, series), curves, first };
}

/** Matches macOS Benchmark.level: CDI before the day; IPCA pro rata by calendar days. */
export function rateBenchmarkLevels(days: DayKey[], rates: NonNullable<OverviewMarket['rates']>, kind: 'cdi' | 'ipca' | 'ipcaPlus6'): ReturnPoint[] {
  const source = kind === 'cdi' ? rates.cdi : rates.ipca;
  if (!source.length) return [];
  const prefix = [1];
  for (const point of source) prefix.push(prefix[prefix.length - 1] * (1 + point.rate / 100));
  return days.filter(day => day >= source[0].day).map(day => {
    let i = 0;
    while (i < source.length && (kind === 'cdi' ? source[i].day < day : Math.floor(source[i].day / 100) < Math.floor(day / 100))) i++;
    let value = prefix[i];
    if (kind !== 'cdi' && i < source.length && Math.floor(source[i].day / 100) === Math.floor(day / 100)) {
      const date = dateFromDay(day);
      const daysInMonth = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
      value *= Math.pow(1 + source[i].rate / 100, (day % 100 - 1) / daysInMonth);
    }
    if (kind === 'ipcaPlus6') value *= Math.pow(1.06, dateFromDay(day).getTime() / (365.25 * 86400000));
    return { day, value };
  });
}

export const percent = (value: number) => `${(value * 100).toLocaleString(undefined, { maximumFractionDigits: 1 })}%`;
