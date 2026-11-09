import type { FundHolding, PriceHistory } from '@/types';

export interface FundReturns {
  month?: number;
  ytd?: number;
  year?: number;
  returnDay?: number;
}
export interface FundValuation extends FundReturns {
  price: number;
  day: number;
  gross: number;
  source: 'CVM daily' | 'CVM monthly' | 'Statement' | 'Open Finance';
}

function shiftMonths(day: number, offset: number): number {
  const year = Math.floor(day / 10000),
    month = Math.floor(day / 100) % 100;
  const first = new Date(Date.UTC(year, month - 1 + offset, 1));
  const last = new Date(
    Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0),
  ).getUTCDate();
  return (
    first.getUTCFullYear() * 10000 +
    (first.getUTCMonth() + 1) * 100 +
    Math.min(day % 100, last)
  );
}

/** Like desktop: trailing calendar month, YTD, trailing year, ending at CVM's last quote. */
export function fundReturns(history?: PriceHistory): FundReturns {
  const day = history?.days.at(-1),
    last = history?.prices.at(-1);
  if (!history || !day || !last) return {};
  function change(start: number) {
    const index = history!.days.findLastIndex((value) => value <= start);
    const base = history!.prices[index];
    return base > 0 ? last! / base - 1 : undefined;
  }
  return {
    month: change(shiftMonths(day, -1)),
    ytd: change((Math.floor(day / 10000) - 1) * 10000 + 1231),
    year: change(shiftMonths(day, -12)),
    returnDay: day,
  };
}

export function fundValuation(
  fund: FundHolding,
  history?: PriceHistory,
): FundValuation | undefined {
  const cvmDay = history?.days.at(-1),
    cvmPrice = history?.prices.at(-1);
  let price = cvmPrice,
    day = cvmDay;
  let source: FundValuation['source'] =
    fund.kind === 'fidc' ? 'CVM monthly' : 'CVM daily';
  if (
    fund.statementPrice &&
    fund.statementDay &&
    fund.statementDay > (day ?? 0)
  ) {
    price = fund.statementPrice;
    day = fund.statementDay;
    source = fund.statementFromOpenFinance ? 'Open Finance' : 'Statement';
  }
  if (!price || !day || !Number.isFinite(price * fund.quantity))
    return undefined;
  return {
    price,
    day,
    source,
    gross: price * fund.quantity,
    ...fundReturns(history),
  };
}

/** Missing histories do not contribute a zero return or dilute the known returns. */
export function weightedFundReturn(
  values: (FundValuation | undefined)[],
  period: 'month' | 'ytd' | 'year',
) {
  let weighted = 0,
    weight = 0;
  for (const value of values) {
    const change = value?.[period];
    if (value && change !== undefined) {
      weighted += value.gross * change;
      weight += value.gross;
    }
  }
  return weight > 0 ? weighted / weight : undefined;
}
export const signedPercent = (value?: number) =>
  value === undefined
    ? '—'
    : value.toLocaleString('pt-BR', {
        style: 'percent',
        maximumFractionDigits: 2,
        minimumFractionDigits: 2,
        signDisplay: 'exceptZero',
      });
