import type { Bond, BondIndexer, BondKind, DayKey, RatePoint } from '@/types';

export const BOND_KINDS: BondKind[] = ['CDB', 'LCA', 'LCI', 'LC', 'CRI', 'CRA', 'Debênture', 'Debênture incentivada'];
export const INDEXERS: BondIndexer[] = ['fixed', 'cdi', 'cdiPlus', 'ipca'];
export const INDEXER_COLORS = { fixed: '#2a78d6', cdi: '#eb6834', cdiPlus: '#eda100', ipca: '#1baf7a' };
export const isTaxExempt = (kind: BondKind) => ['LCA', 'LCI', 'CRI', 'CRA', 'Debênture incentivada'].includes(kind);
export const isFGCCovered = (kind: BondKind) => ['CDB', 'LCA', 'LCI', 'LC'].includes(kind);
export const money = (value: number) => value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const number = (value: number) => value.toLocaleString('pt-BR', { maximumFractionDigits: 6 });
export const invested = (bond: Bond) => bond.quantity * bond.unitPrice;
export function describeRate(bond: Bond) {
  const rate = bond.rate.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return { fixed: `${rate}% a.a.`, cdi: `${rate}% do CDI`, cdiPlus: `CDI + ${rate}%`, ipca: `IPCA + ${rate}%` }[bond.indexer];
}
export function dateFromDay(day: DayKey) {
  return new Date(Date.UTC(Math.floor(day / 10000), Math.floor(day / 100) % 100 - 1, day % 100));
}
export function dayFromDate(date: Date): DayKey {
  return date.getUTCFullYear() * 10000 + (date.getUTCMonth() + 1) * 100 + date.getUTCDate();
}
export function today(): DayKey {
  const date = new Date();
  return date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
}
export const formatDay = (day: DayKey) => dateFromDay(day).toLocaleDateString('pt-BR', { timeZone: 'UTC' });
function nextDay(day: DayKey) { return dayFromDate(new Date(dateFromDay(day).getTime() + 86400000)); }
function anniversary(anchor: number, day: DayKey, offset = 0) {
  const date = dateFromDay(day);
  const end = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + offset + 1, 0));
  return dayFromDate(new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), Math.min(anchor, end.getUTCDate()))));
}
const holidayCache = new Map<number, Set<number>>();
function holidays(year: number) {
  const cached = holidayCache.get(year);
  if (cached) return cached;
  const days = new Set([101, 421, 501, 907, 1012, 1102, 1115, 1225].map(md => year * 10000 + md));
  if (year >= 2024) days.add(year * 10000 + 1120);
  const a = year % 19, b = Math.floor(year / 100), c = year % 100;
  const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
  const easter = Date.UTC(year, Math.floor((h + l - 7 * m + 114) / 31) - 1, (h + l - 7 * m + 114) % 31 + 1);
  for (const offset of [-48, -47, -2, 60]) days.add(dayFromDate(new Date(easter + offset * 86400000)));
  holidayCache.set(year, days);
  return days;
}
export function businessDays(start: DayKey, end: DayKey) {
  let count = 0;
  for (let day = start; day < end; day = nextDay(day)) {
    const weekday = dateFromDay(day).getUTCDay();
    if (weekday !== 0 && weekday !== 6 && !holidays(Math.floor(day / 10000)).has(day)) count++;
  }
  return count;
}
export function incomeTaxRate(days: number) { return days <= 180 ? .225 : days <= 360 ? .20 : days <= 720 ? .175 : .15; }
export function iofRate(days: number) {
  const rates = [96,93,90,86,83,80,76,73,70,66,63,60,56,53,50,46,43,40,36,33,30,26,23,20,16,13,10,6,3,0];
  return days < 1 ? 1 : days >= 30 ? 0 : rates[days - 1] / 100;
}
export interface BondRates { cdi: RatePoint[]; ipca: RatePoint[] }
export interface BondValuation { unitValue: number; gross: number; incomeTax: number; iof: number; net: number; gain: number; atMaturity?: number }
export function valueBond(bond: Bond, rates: BondRates | null, day = today()): BondValuation | null {
  if (bond.issueDay > day) return null;
  const end = Math.min(day, bond.maturityDay);
  if (bond.indexer !== 'fixed' && !rates) return null;
  const cdi = rates?.cdi ?? [], ipca = rates?.ipca ?? [];
  if ((bond.indexer === 'cdi' || bond.indexer === 'cdiPlus') && !cdi.length) return null;
  if (bond.indexer === 'ipca' && !ipca.length) return null;
  const latestCDI = (cdi.at(-1)?.rate ?? 0) / 100;
  let factor = Math.pow(1 + bond.rate / 100, businessDays(bond.issueDay, end) / 252);
  if (bond.indexer === 'cdi' || bond.indexer === 'cdiPlus') {
    const share = bond.indexer === 'cdi' ? bond.rate / 100 : 1;
    let cdiFactor = 1;
    let lastDay = bond.issueDay;
    for (const point of cdi) {
      if (point.day < bond.issueDay || point.day >= end) continue;
      cdiFactor *= 1 + share * point.rate / 100;
      lastDay = nextDay(point.day);
    }
    cdiFactor *= Math.pow(1 + share * latestCDI, businessDays(lastDay, end));
    factor = cdiFactor * (bond.indexer === 'cdiPlus' ? factor : 1);
  } else if (bond.indexer === 'ipca') {
    let inflation = 1;
    let start = bond.issueDay;
    while (start < end) {
      const stop = anniversary(bond.issueDay % 100, start, 1);
      const publishedMonth = Math.floor(anniversary(1, stop, stop % 100 > 10 ? -1 : -2) / 100);
      const rate = ipca.find(p => Math.floor(p.day / 100) === publishedMonth)?.rate ?? ipca.at(-1)!.rate;
      inflation *= Math.pow(1 + rate / 100, businessDays(start, Math.min(stop, end)) / Math.max(1, businessDays(start, stop)));
      start = stop;
    }
    factor *= inflation;
  }
  const gross = invested(bond) * factor, gain = gross - invested(bond);
  const held = Math.floor((dateFromDay(day).getTime() - dateFromDay(bond.issueDay).getTime()) / 86400000);
  const incomeTax = isTaxExempt(bond.kind) ? 0 : Math.max(0, gain) * incomeTaxRate(held);
  const iof = Math.max(0, gain) * iofRate(held);
  const remaining = businessDays(day, bond.maturityDay);
  const trailingIPCA = ipca.slice(-12).reduce((f, p) => f * (1 + p.rate / 100), 1);
  const ahead = { fixed: Math.pow(1 + bond.rate / 100, remaining / 252), cdi: Math.pow(1 + bond.rate / 100 * latestCDI, remaining), cdiPlus: Math.pow(1 + latestCDI, remaining) * Math.pow(1 + bond.rate / 100, remaining / 252), ipca: Math.pow(trailingIPCA * (1 + bond.rate / 100), remaining / 252) }[bond.indexer];
  return { unitValue: bond.unitPrice * factor, gross, incomeTax, iof, net: gross - incomeTax - iof, gain, atMaturity: day < bond.maturityDay ? gross * ahead : undefined };
}

/** Public market data only; never touches personal Open Finance accounts. */
export async function fetchBondRates(start: DayKey, signal: AbortSignal): Promise<BondRates> {
  async function series(code: number) {
    const url = `https://api.bcb.gov.br/dados/serie/bcdata.sgs.${code}/dados?formato=json&dataInicial=${formatDay(start)}&dataFinal=${formatDay(today())}`;
    const response = await fetch(url, { signal });
    if (!response.ok) throw new Error('Rate history unavailable');
    const data: unknown = await response.json();
    if (!Array.isArray(data) || !data.length) throw new Error('Empty rate history');
    return data.map((point: { data: string; valor: string }) => {
      const [d, m, y] = point.data.split('/').map(Number);
      const rate = Number(point.valor);
      if (!Number.isFinite(rate)) throw new Error('Invalid rate');
      return { day: y * 10000 + m * 100 + d, rate };
    }).sort((a, b) => a.day - b.day);
  }
  const [cdi, ipca] = await Promise.all([series(12), series(433)]);
  return { cdi, ipca };
}
