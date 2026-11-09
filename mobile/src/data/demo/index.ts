import alerts from './alerts.json';
import bonds from './bonds.json';
import expenses from './expenses.json';
import fundHoldings from './fund-holdings.json';
import trades from './trades.json';
import transactions from './transactions-by-month.json';
import type { DayKey, DemoData } from '../../types';

/** Last month in the source fixtures; matches macOS DataAccount.demoMonth. */
export const DEMO_BASE_MONTH = 202610;

const seed = { trades, bonds, fundHoldings, alerts, expenses, transactions } as DemoData;

function localToday(): DayKey {
  const now = new Date();
  return now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
}

function moveMonth(month: number, offset: number): number {
  const date = new Date(Date.UTC(Math.floor(month / 100), month % 100 - 1 + offset, 1));
  return date.getUTCFullYear() * 100 + date.getUTCMonth() + 1;
}

function shiftDate(iso: string, offset: number): string {
  const month = moveMonth(Number(iso.slice(0, 4)) * 100 + Number(iso.slice(5, 7)), offset);
  const year = Math.floor(month / 100);
  const m = month % 100;
  const day = Math.min(Number(iso.slice(8, 10)), new Date(Date.UTC(year, m, 0)).getUTCDate());
  return `${year}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}${iso.slice(10)}`;
}

/**
 * Fresh in-memory demo account; never reads credentials, persists preferences or calls Pluggy.
 * Like macOS, shift transactions to this month, clamp month ends and omit future rows.
 * Trades, bonds and fund terms keep their original dates. Pass YYYYMMDD for repeatable previews.
 */
export function createDemoData(today: DayKey = localToday()): DemoData {
  const year = Math.floor(today / 10000);
  const month = Math.floor(today / 100) % 100;
  const day = today % 100;
  if (!Number.isInteger(today) || year < 1900 || year > 9999 || month < 1 || month > 12
    || day < 1 || day > new Date(Date.UTC(year, month, 0)).getUTCDate()) {
    throw new RangeError('today must be a valid YYYYMMDD calendar date');
  }
  // JSON cloning works on both native runtimes, and callers can edit their copy freely.
  const data: DemoData = JSON.parse(JSON.stringify(seed));
  const offset = (year - Math.floor(DEMO_BASE_MONTH / 100)) * 12 + month - DEMO_BASE_MONTH % 100;
  const shifted: DemoData['transactions']['months'] = {};
  for (const [key, rows] of Object.entries(data.transactions.months)) {
    shifted[String(moveMonth(Number(key), offset))] = rows.flatMap((row) => {
      if (!row.date) return [];
      const date = shiftDate(row.date, offset);
      if (Number(date.slice(0, 10).replaceAll('-', '')) > today) return [];
      return [{
        ...row,
        date,
        ...(row.creditCardMetadata?.purchaseDate ? {
          creditCardMetadata: {
            ...row.creditCardMetadata,
            purchaseDate: shiftDate(row.creditCardMetadata.purchaseDate, offset),
          },
        } : {}),
      }];
    });
  }
  data.transactions.months = shifted;
  // Preserve the desktop cache's Apple epoch convention and its never-stale demo marker.
  data.transactions.fetchedAt = Object.fromEntries(Object.keys(shifted).map((key) => [key, 4_000_000_000]));
  data.transactions.currencyRead = Object.keys(shifted).map(Number);
  return data;
}
