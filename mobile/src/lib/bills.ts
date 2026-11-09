import type { BillChoice, DemoData, Expense, ExpenseSettings, ExpenseSource, PluggyTransaction, RecurringBill } from '../types';

export function todayKey(): number {
  const now = new Date();
  return now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
}

export function calendarDate(day: number): Date {
  return new Date(Date.UTC(Math.floor(day / 10000), Math.floor(day / 100) % 100 - 1, day % 100));
}

export function monthOffset(month: number, offset: number): number {
  const date = new Date(Date.UTC(Math.floor(month / 100), month % 100 - 1 + offset, 1));
  return date.getUTCFullYear() * 100 + date.getUTCMonth() + 1;
}

export function dueDate(day: number, month: number): number {
  const last = new Date(Date.UTC(Math.floor(month / 100), month % 100, 0)).getUTCDate();
  return month * 100 + Math.min(day, last);
}

export function daysBetween(from: number, to: number): number {
  return Math.round((calendarDate(to).getTime() - calendarDate(from).getTime()) / 86_400_000);
}

function fold(value: string): string {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase();
}

export function merchantKey(value: string): string {
  return fold(value).replace(/[^\p{L}\p{N}]/gu, '');
}

function sourceOf(row: PluggyTransaction, isCard: boolean): ExpenseSource {
  if (isCard) return 'creditCard';
  const method = row.paymentData?.paymentMethod?.toUpperCase();
  const text = fold(`${row.description ?? ''} ${row.descriptionRaw ?? ''}`);
  if (method === 'PIX' || text.includes('PIX')) return 'pix';
  if (['COMPRA DEBITO', 'DEBITO VISA', 'DEBITO MASTER', 'CARTAO DEBITO', 'COMPRA CARTAO'].some((s) => text.includes(s))
    || row.category?.toLowerCase().includes('debit card')) return 'debitCard';
  if (['DEBITO AUTOMATICO', 'DEB AUTOMATICO', 'DEB.AUT'].some((s) => text.includes(s))) return 'autoDebit';
  if (method === 'BOLETO' || text.includes('BOLETO') || text.includes('PAGAMENTO DE TITULO')) return 'boleto';
  if (['TED', 'DOC', 'TEF'].includes(method ?? '') || ['TED ', 'DOC ', 'TRANSF'].some((s) => text.includes(s))) return 'transfer';
  return 'account';
}

/** Desktop classification, with foreign amounts left unavailable unless the bank supplied BRL. */
export function classifyExpenses(data: DemoData): Expense[] {
  const settings = data.expenses;
  const transactions = Object.values(data.transactions.months).flat();
  const seen = new Set<string>();
  const rows: Expense[] = [];
  const accounts = new Map(data.transactions.accounts.map((a) => [a.id, a]));
  for (const row of transactions) {
    const override = settings.overrides[row.id];
    if (!row.date || override?.deleted || seen.has(row.id)) continue;
    seen.add(row.id);
    const account = accounts.get(row.accountId ?? '');
    const isCard = account?.type === 'CREDIT';
    const credit = row.type === 'CREDIT';
    const party = credit ? row.paymentData?.payer?.name : row.paymentData?.receiver?.name;
    const store = [row.merchant?.businessName, row.merchant?.name, party, row.description]
      .find((s) => s?.trim())?.trim() ?? '—';
    const key = merchantKey(store);
    const category = (row.category ?? row.merchant?.category ?? '').toLowerCase();
    const text = fold(`${row.descriptionRaw ?? ''} ${row.description ?? ''}`);
    const outside = (isCard && credit)
      || ['credit card payment', 'same ownership', 'same person', 'investment', 'proceeds', 'savings'].some((s) => category.includes(s))
      || ['PAGAMENTO FATURA', 'PAG FATURA', 'PGTO FATURA', 'FATURA CARTAO', 'APLICACAO', 'RESGATE', 'CDB', 'TESOURO', 'TED MESMA TITULARIDADE', 'TRANSF ENTRE CONTAS'].some((s) => text.includes(s));
    let kind: Expense['kind'] = outside ? 'outside' : credit ? 'income' : 'spending';
    let categoryID: string | undefined = settings.rules[key] ?? settings.categories.find((c) => c.pluggyKeywords.some((s) => category.includes(s.toLowerCase())))?.id;
    if (override?.category) {
      categoryID = override.category._0;
      if (kind === 'outside') kind = credit && !isCard ? 'income' : 'spending';
    }
    if (override?.outside) { kind = 'outside'; categoryID = undefined; }
    const foreign = row.currencyCode && row.currencyCode.toUpperCase() !== 'BRL';
    rows.push({ id: row.id, day: Number(row.date.slice(0, 10).replaceAll('-', '')), store,
      detail: row.descriptionRaw ?? row.description ?? '', amount: Math.abs(foreign ? row.amountInAccountCurrency ?? 0 : row.amount ?? 0),
      kind, categoryID, accountName: account?.marketingName ?? account?.name ?? undefined,
      isCard, isManual: false, merchantKey: key, source: sourceOf(row, isCard), billedLater: false });
  }
  for (const row of settings.manual) {
    const override = settings.overrides[row.id];
    if (override?.deleted) continue;
    rows.push({ ...row, detail: '', kind: override?.outside ? 'outside' : 'spending',
      categoryID: override?.category?._0 ?? row.categoryID, isCard: false, isManual: true,
      merchantKey: merchantKey(row.store), source: 'manual', billedLater: false });
  }
  return rows;
}

export function billKey(row: Expense): string {
  return row.source === 'autoDebit' ? `debit:${merchantKey(row.detail.replace(/\p{N}/gu, ''))}` : row.merchantKey;
}

export function financing(detail: string): RecurringBill['installment'] {
  const match = fold(detail).match(/PARCELA\s+(\d{1,3})\s*(?:DE|\/)\s*(\d{1,3})/);
  if (!match || Number(match[2]) <= 1 || Number(match[1]) > Number(match[2])) return undefined;
  return { number: Number(match[1]), total: Number(match[2]) };
}

export function recurringBills(expenses: Expense[], choices: Record<string, BillChoice>, today: number): RecurringBill[] {
  const month = Math.floor(today / 100);
  const previous = [1, 2, 3].map((n) => monthOffset(month, -n));
  const previousMonths = new Set(previous);
  const groups = new Map<string, Expense[]>();
  for (const row of expenses) {
    const key = billKey(row);
    const m = Math.floor(row.day / 100);
    if (row.isCard || row.kind === 'income' || row.amount <= 0 || m > month || row.day > today) continue;
    if (m < previous[2] && choices[key]?.tracked !== true) continue;
    groups.set(key, [...groups.get(key) ?? [], row]);
  }
  const bills: RecurringBill[] = [];
  for (const [key, payments] of groups) {
    const choice = choices[key] ?? {};
    if (choice.tracked === false) continue;
    const looksLikeBill = payments.some((p) => p.kind !== 'outside' && (p.source === 'boleto' || p.source === 'autoDebit' || financing(p.detail)));
    const months = new Set(payments.map((p) => Math.floor(p.day / 100)).filter((m) => previousMonths.has(m)));
    if (choice.tracked !== true && (!looksLikeBill || months.size < 2)) continue;
    const sorted = payments.toSorted((a, b) => a.day - b.day);
    const lastPayment = sorted[sorted.length - 1];
    const past = sorted.filter((p) => Math.floor(p.day / 100) < month);
    const days = (past.length ? past.slice(-3) : sorted).map((p) => p.day % 100).sort((a, b) => a - b);
    const dueDay = choice.dueDay ?? days[Math.floor(days.length / 2)];
    const totals = new Map<number, number>();
    for (const p of past.slice(-6)) {
      const m = Math.floor(p.day / 100);
      totals.set(m, (totals.get(m) ?? 0) + p.amount);
    }
    const usual = totals.size ? [...totals.values()].reduce((sum, n) => sum + n, 0) / totals.size : lastPayment.amount;
    const paidThisMonth = sorted.filter((p) => Math.floor(p.day / 100) === month);
    const paidByHand = choice.paidByHand?.includes(month) ?? false;
    const paid = paidThisMonth.length > 0 || paidByHand;
    const due = dueDate(dueDay, month);
    const installment = sorted.toReversed().map((p) => financing(p.detail)).find(Boolean);
    bills.push({ key, name: lastPayment.store, source: lastPayment.source, dueDay, dueDaySet: choice.dueDay != null,
      usual, lastPayment, paidThisMonth, paidByHand, installment, trackedByHand: choice.tracked === true,
      nextDue: paid ? dueDate(dueDay, monthOffset(month, 1)) : due,
      status: paid ? 'paid' : daysBetween(due, today) > 3 ? 'late' : 'upcoming' });
  }
  return bills.sort((a, b) => a.dueDay - b.dueDay || a.name.localeCompare(b.name));
}

export function upcomingBills(bills: RecurringBill[], today: number): RecurringBill[] {
  return bills.filter((b) => b.status === 'late' || daysBetween(today, b.nextDue) <= 30)
    .toSorted((a, b) => Number(b.status === 'late') - Number(a.status === 'late') || a.nextDue - b.nextDue || a.name.localeCompare(b.name));
}

export function withBillChoice(settings: ExpenseSettings, key: string, change: Partial<BillChoice>): ExpenseSettings {
  return { ...settings, bills: { ...settings.bills, [key]: { ...settings.bills?.[key], ...change } } };
}

/** Latest eligible payment per merchant, for the manual tracking picker. */
export function trackablePayments(expenses: Expense[], recurring: RecurringBill[], choices: Record<string, BillChoice>, today: number): Map<string, Expense> {
  const activeKeys = new Set(recurring.map((b) => b.key));
  const candidates = new Map<string, Expense>();
  for (const row of expenses.toSorted((a, b) => a.day - b.day)) {
    const key = billKey(row);
    if (!row.isCard && row.kind === 'spending' && row.amount > 0 && row.day <= today && !activeKeys.has(key) && choices[key]?.tracked !== false) candidates.set(key, row);
  }
  return candidates;
}
