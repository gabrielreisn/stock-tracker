import type { Expense, ExpenseSettings, PluggyTransaction, TransactionCache } from '@/types';

/** Desktop ExpenseStore classification, kept independent of personal stores and network access. */
export function classifyExpenses(cache: TransactionCache, settings: ExpenseSettings): Expense[] {
  const accounts = new Map(cache.accounts.map((account) => [account.id, account]));
  const categoriesByID = new Map(settings.categories.map((category) => [category.id, category]));
  const seen = new Set<string>();
  const rows: Expense[] = [];
  for (const transaction of Object.values(cache.months).flat()) {
    if (seen.has(transaction.id)) continue;
    seen.add(transaction.id);
    const override = settings.overrides[transaction.id];
    if (override?.deleted) continue;
    const account = accounts.get(transaction.accountId ?? '');
    const isCard = account?.type === 'CREDIT';
    const credit = transaction.type?.toUpperCase() === 'CREDIT';
    const party = credit ? transaction.paymentData?.payer?.name : transaction.paymentData?.receiver?.name;
    const store = [transaction.merchant?.businessName, transaction.merchant?.name, party, transaction.description]
      .find((name) => name?.trim())?.trim() ?? '—';
    const merchantKey = store.normalize('NFD').replace(/\p{M}/gu, '').toUpperCase().replace(/[^\p{L}\p{N}]/gu, '');
    let kind: Expense['kind'] = looksOutside(transaction, isCard) ? 'outside' : credit ? 'income' : 'spending';
    const category = (transaction.category ?? transaction.merchant?.category ?? '').toLowerCase();
    const rule = settings.rules[merchantKey];
    let categoryID = kind === 'spending'
      ? categoriesByID.get(rule)?.id
        ?? settings.categories.find((item) => item.pluggyKeywords.some((keyword) => category.includes(keyword.toLowerCase())))?.id
      : undefined;
    if (override?.category) {
      categoryID = override.category._0;
      if (kind === 'outside') kind = credit && !isCard ? 'income' : 'spending';
    }
    if (override?.outside) { kind = 'outside'; categoryID = undefined; }
    let day = Number(transaction.date?.slice(0, 10).replaceAll('-', '') ?? 0);
    if (!day) continue;
    const metadata = transaction.creditCardMetadata;
    const installment = metadata?.installmentNumber ?? 1;
    const billedLater = installment > 1 && (metadata?.totalInstallments ?? 0) > 1;
    if (billedLater) {
      const purchase = metadata?.purchaseDate ?? transaction.date!;
      const date = new Date(Date.UTC(Number(purchase.slice(0, 4)), Number(purchase.slice(5, 7)) - 1 + installment - 1, 1));
      day = date.getUTCFullYear() * 10000 + (date.getUTCMonth() + 1) * 100 + 1;
    }
    const foreign = transaction.currencyCode && transaction.currencyCode.toUpperCase() !== 'BRL';
    // Never add an unconverted foreign amount to BRL totals.
    const amount = Math.abs(foreign ? transaction.amountInAccountCurrency ?? 0 : transaction.amount ?? 0);
    rows.push({ id: transaction.id, day, store, detail: transaction.descriptionRaw ?? transaction.description ?? '',
      amount, kind, categoryID, accountName: account?.marketingName ?? account?.name ?? undefined,
      isCard, isManual: false, merchantKey, source: isCard ? 'creditCard' : 'account', billedLater });
  }
  for (const manual of settings.manual) {
    const override = settings.overrides[manual.id];
    if (override?.deleted) continue;
    rows.push({ ...manual, detail: '', kind: override?.outside ? 'outside' : 'spending',
      categoryID: override?.outside ? undefined : override?.category?._0 ?? manual.categoryID,
      isCard: false, isManual: true, merchantKey: '', source: 'manual', billedLater: false });
  }
  return rows;
}

function looksOutside(transaction: PluggyTransaction, isCard: boolean): boolean {
  if (isCard && transaction.type?.toUpperCase() === 'CREDIT') return true;
  const category = (transaction.category ?? '').toLowerCase();
  const text = `${transaction.descriptionRaw ?? ''} ${transaction.description ?? ''}`.toUpperCase();
  return ['credit card payment', 'same ownership', 'same person', 'investment', 'proceeds', 'savings'].some((term) => category.includes(term))
    || ['PAGAMENTO FATURA', 'PAG FATURA', 'PGTO FATURA', 'FATURA CARTAO', 'APLICACAO', 'RESGATE', 'CDB', 'TESOURO',
      'TED MESMA TITULARIDADE', 'TRANSF ENTRE CONTAS'].some((term) => text.includes(term));
}

export type Focus = 'all' | string | null;
export interface MonthPoint { month: number; amount: number; finished: boolean }

/** Least squares over completed months from the first nonzero value, matching macOS. */
export function spendingTrend(series: MonthPoint[]) {
  const done = series.filter((point) => point.finished);
  const start = done.findIndex((point) => point.amount > 0);
  const points = done.slice(start);
  if (start < 0 || points.length < 3) return null;
  const mx = (points.length - 1) / 2;
  const average = points.reduce((sum, point) => sum + point.amount, 0) / points.length;
  const denominator = points.reduce((sum, _, i) => sum + (i - mx) ** 2, 0);
  const slope = points.reduce((sum, point, i) => sum + (i - mx) * (point.amount - average), 0) / denominator;
  const intercept = average - slope * mx;
  return { slope, points: points.map((point, i) => ({ ...point, amount: Math.max(0, intercept + slope * i) })) };
}

export function finishedAverage(series: MonthPoint[]) {
  const done = series.filter((point) => point.finished);
  return done.length ? done.reduce((sum, point) => sum + point.amount, 0) / done.length : 0;
}

export function buildYearData(expenses: Expense[], settings: ExpenseSettings, year: number, currentMonth: number) {
  const yearMonths = Array.from({ length: 12 }, (_, index) => year * 100 + index + 1);
  const available = yearMonths.filter((month) => month <= currentMonth);
  const availableMonths = new Set(available);
  const categoriesByID = new Map(settings.categories.map((category) => [category.id, category]));
  const spent = new Map<number, Map<string | null, number>>();
  let totalIncome = 0;
  for (const expense of expenses) {
    const month = Math.floor(expense.day / 100);
    if (!availableMonths.has(month)) continue;
    if (expense.kind === 'income') totalIncome += expense.amount;
    if (expense.kind !== 'spending') continue;
    const categories = spent.get(month) ?? new Map<string | null, number>();
    const id = expense.categoryID ?? null;
    categories.set(id, (categories.get(id) ?? 0) + expense.amount);
    spent.set(month, categories);
  }
  const amount = (id: string | null, month: number) => spent.get(month)?.get(id) ?? 0;
  const monthTotal = (month: number) => Array.from(spent.get(month)?.values() ?? []).reduce((sum, value) => sum + value, 0);
  const first = available.findIndex((month) => monthTotal(month) > 0);
  const months = first < 0 ? [] : available.slice(first);
  const totals = new Map<string | null, number>();
  for (const categories of spent.values()) {
    for (const [id, value] of categories) totals.set(id, (totals.get(id) ?? 0) + value);
  }
  const rows = Array.from(totals, ([id, total]) => ({ id, total, category: id === null ? undefined : categoriesByID.get(id) }))
    .filter((row) => row.total > 0).sort((a, b) => b.total - a.total);
  const series = (focus: Focus): MonthPoint[] => months.map((month) => ({ month,
    amount: focus === 'all' ? monthTotal(month) : amount(focus, month), finished: month < currentMonth }));
  const all = series('all');
  const finished = all.filter((point) => point.finished);
  const averageBase = finished.length ? finished : all;
  return { yearMonths, months, rows, series, amount, monthTotal, totalIncome,
    totalSpent: all.reduce((sum, point) => sum + point.amount, 0),
    averageSpent: averageBase.length ? averageBase.reduce((sum, point) => sum + point.amount, 0) / averageBase.length : 0,
    highestMonth: all.filter((point) => point.amount > 0).sort((a, b) => b.amount - a.amount)[0],
    lastFinished: finished.at(-1)?.month };
}
