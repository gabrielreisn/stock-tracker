import type { CardBillGroup, PluggyAccount, PluggyBill } from '../types';

/** One card with its statements ordered newest first; never modifies the bank's cache. */
export function groupCardBills(bills: PluggyBill[], accounts: PluggyAccount[]): CardBillGroup[] {
  const accountByID = new Map(accounts.map((account) => [account.id, account]));
  const groups = new Map<string, CardBillGroup>();
  for (const bill of bills) {
    // Without an account ID, keep statements separate rather than guessing their card.
    const key = bill.accountId ?? `bill:${bill.id}`;
    const group = groups.get(key) ?? { key, account: accountByID.get(key), bills: [] };
    group.bills.push(bill);
    groups.set(key, group);
  }
  for (const group of groups.values()) {
    group.bills.sort((a, b) => (b.dueDate ?? b.billClosingDate ?? '').localeCompare(a.dueDate ?? a.billClosingDate ?? '') || a.id.localeCompare(b.id));
  }
  return [...groups.values()];
}

export function cardBillPayment(bill: PluggyBill) {
  const amounts = (bill.payments ?? []).flatMap((payment) =>
    payment.amount != null && Number.isFinite(payment.amount) ? [Math.abs(payment.amount)] : []);
  const paid = amounts.length ? amounts.reduce((sum, amount) => sum + amount, 0) : undefined;
  const total = bill.totalAmount;
  const hasTotal = total != null && Number.isFinite(total);
  const remaining = hasTotal && paid != null ? Math.max(0, total - paid) : undefined;
  let status: 'paid' | 'partial' | 'unreported' | 'empty' = 'unreported';
  if (hasTotal && total <= 0.5) status = 'empty';
  else if (hasTotal && paid != null && paid >= total - 1) status = 'paid';
  else if (paid != null && paid > 0) status = 'partial';
  return { paid, remaining, status };
}
