import type { Expense, ExpenseSettings, MonthKey } from '../types';
import { spendingByCategory } from './expenses';

export type ExpenseAlert =
  | { key: string; kind: 'warning' | 'over'; name: string; spent: number; limit: number; percent: number }
  | { key: string; kind: 'purchase'; store: string; amount: number };

/** Stable desktop-compatible keys survive edits, refreshes and app restarts. */
export function pendingExpenseAlerts(settings: ExpenseSettings, rows: Expense[], month: MonthKey): ExpenseAlert[] {
  const sent = new Set(settings.notified);
  const spending = spendingByCategory(rows, month);
  const alerts: ExpenseAlert[] = [];
  function check(id: string, name: string, spent: number, limit?: number) {
    if (!limit || limit <= 0 || spent < limit * settings.alertAt) return;
    const kind = spent > limit ? 'over' : 'warning';
    const key = `${month}|${id}|${kind === 'over' ? 'over' : 'warn'}`;
    // After an over-limit warning, lowering spending must not send an older warning.
    if (sent.has(key) || (kind === 'warning' && sent.has(`${month}|${id}|over`))) return;
    alerts.push({ key, kind, name, spent, limit, percent: Math.round(spent / limit * 100) });
  }
  for (const category of settings.categories) check(category.id, category.name, spending.get(category.id) ?? 0, category.limit);
  check('total', 'Monthly total', [...spending.values()].reduce((sum, amount) => sum + amount, 0), settings.totalLimit);
  if (settings.largePurchase && settings.largePurchase > 0) {
    for (const row of rows) {
      const key = `big|${row.id}`;
      if (row.kind === 'spending' && Math.floor(row.day / 100) === month && !row.billedLater
        && row.amount > settings.largePurchase && !sent.has(key)) {
        alerts.push({ key, kind: 'purchase', store: row.store, amount: row.amount });
      }
    }
  }
  return alerts;
}
