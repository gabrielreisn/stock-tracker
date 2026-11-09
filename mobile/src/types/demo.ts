import type { ExpenseSettings } from './expenses';
import type { PluggyAccount, PluggyTransaction } from './pluggy';
import type { AppleTimestamp, Bond, FundHolding, MonthKey, PriceAlert, Trade } from './portfolio';

export interface TransactionCache {
  months: Record<string, PluggyTransaction[]>;
  fetchedAt: Record<string, AppleTimestamp>;
  accounts: PluggyAccount[];
  currencyRead?: MonthKey[];
}

export interface DemoData {
  trades: Trade[];
  bonds: Bond[];
  fundHoldings: FundHolding[];
  alerts: PriceAlert[];
  expenses: ExpenseSettings;
  transactions: TransactionCache;
}
