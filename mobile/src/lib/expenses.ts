import type { Expense, ExpenseCategory, ExpenseSettings, MonthKey, PluggyTransaction, ExpenseSource, TransactionCache } from '../types';

export function moveMonth(month: MonthKey, offset: number): MonthKey {
  const date = new Date(Date.UTC(Math.floor(month / 100), month % 100 - 1 + offset, 1));
  return date.getUTCFullYear() * 100 + date.getUTCMonth() + 1;
}

export function merchantKey(name: string): string {
  return name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^\p{L}\p{N}]/gu, '');
}

function sourceOf(row: PluggyTransaction, isCard: boolean): ExpenseSource {
  if (isCard) return 'creditCard';
  const method = row.paymentData?.paymentMethod?.toUpperCase();
  const text = `${row.description ?? ''} ${row.descriptionRaw ?? ''}`.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase();
  if (method === 'PIX' || text.includes('PIX')) return 'pix';
  if (['COMPRA DEBITO', 'DEBITO VISA', 'DEBITO MASTER', 'CARTAO DEBITO', 'COMPRA CARTAO'].some((s) => text.includes(s))
    || row.category?.toLowerCase().includes('debit card')) return 'debitCard';
  if (['DEBITO AUTOMATICO', 'DEB AUTOMATICO', 'DEB.AUT'].some((s) => text.includes(s))) return 'autoDebit';
  if (method === 'BOLETO' || text.includes('BOLETO') || text.includes('PAGAMENTO DE TITULO')) return 'boleto';
  if (['TED', 'DOC', 'TEF'].includes(method ?? '') || ['TED ', 'DOC ', 'TRANSF'].some((s) => text.includes(s))) return 'transfer';
  return 'account';
}

/** Desktop classification order: exclusions, merchant rules, keyword mapping, then overrides. */
export function classifyExpenses(cache: TransactionCache, settings: ExpenseSettings): Expense[] {
  const accounts = new Map(cache.accounts.map((account) => [account.id, account]));
  const categories = new Set(settings.categories.map((category) => category.id));
  const transactions = new Map(Object.values(cache.months).flat().map((row) => [row.id, row]));
  const rows: Expense[] = [];
  for (const transaction of transactions.values()) {
    const override = settings.overrides[transaction.id];
    if (override?.deleted || !transaction.date) continue;
    const account = accounts.get(transaction.accountId ?? '');
    const isCard = account?.type === 'CREDIT';
    const isCredit = transaction.type?.toUpperCase() === 'CREDIT';
    const party = isCredit ? transaction.paymentData?.payer?.name : transaction.paymentData?.receiver?.name;
    const store = [transaction.merchant?.businessName, transaction.merchant?.name, party, transaction.description]
      .find((name) => name?.trim())?.trim() ?? '—';
    const key = merchantKey(store);
    const categoryText = (transaction.category ?? transaction.merchant?.category ?? '').toLowerCase();
    const text = `${transaction.descriptionRaw ?? ''} ${transaction.description ?? ''}`.toUpperCase();
    const outside = (isCard && isCredit)
      || ['credit card payment', 'same ownership', 'same person', 'investment', 'proceeds', 'savings'].some((word) => categoryText.includes(word))
      || ['PAGAMENTO FATURA', 'PAG FATURA', 'PGTO FATURA', 'FATURA CARTAO', 'APLICACAO', 'RESGATE', 'CDB', 'TESOURO', 'TED MESMA TITULARIDADE', 'TRANSF ENTRE CONTAS'].some((word) => text.includes(word));
    let kind: Expense['kind'] = outside ? 'outside' : isCredit ? 'income' : 'spending';
    const rule = settings.rules[key];
    let categoryID = kind === 'spending' ? (categories.has(rule) ? rule : settings.categories.find((category) =>
      category.pluggyKeywords.some((keyword) => categoryText.includes(keyword.toLowerCase())))?.id) : undefined;
    if (override?.category && categories.has(override.category._0)) {
      categoryID = override.category._0;
      if (kind === 'outside') kind = isCredit && !isCard ? 'income' : 'spending';
    } else if (override?.outside) {
      kind = 'outside';
      categoryID = undefined;
    }
    let day = Number(transaction.date.slice(0, 10).replaceAll('-', ''));
    const metadata = transaction.creditCardMetadata;
    const installment = metadata?.installmentNumber;
    const total = metadata?.totalInstallments;
    const billedLater = !!(installment && total && total > 1 && installment > 1);
    if (billedLater) {
      const purchase = metadata?.purchaseDate ?? transaction.date;
      const purchaseMonth = Number(purchase.slice(0, 7).replace('-', ''));
      day = moveMonth(purchaseMonth, installment! - 1) * 100 + 1;
    }
    const original = Math.abs(transaction.amount ?? 0);
    const currency = transaction.currencyCode?.toUpperCase();
    const foreign = currency && currency !== 'BRL';
    const converted = transaction.amountInAccountCurrency;
    const amount = foreign ? Math.abs(converted ?? 0) : original;
    rows.push({
      id: transaction.id, day, store, detail: transaction.descriptionRaw ?? transaction.description ?? '',
      amount, kind, categoryID, accountName: account?.marketingName ?? account?.name ?? undefined,
      isCard, isManual: false, merchantKey: key, source: sourceOf(transaction, isCard), billedLater,
      installment: installment && total && total > 1 ? `${installment}/${total}` : undefined,
      foreign: foreign ? { amount: original, currency, conversion: converted == null ? { kind: 'missing' } : { kind: 'bank' } } : undefined,
    });
  }
  for (const manual of settings.manual) {
    const override = settings.overrides[manual.id];
    if (override?.deleted) continue;
    const id = override?.category?._0 ?? manual.categoryID;
    rows.push({
      ...manual, detail: '', kind: override?.outside ? 'outside' : 'spending',
      categoryID: !override?.outside && id && categories.has(id) ? id : undefined,
      isCard: false, isManual: true, merchantKey: merchantKey(manual.store), source: 'manual', billedLater: false,
    });
  }
  return rows;
}

export function spendingByCategory(rows: Expense[], month: MonthKey): Map<string | undefined, number> {
  const totals = new Map<string | undefined, number>();
  for (const row of rows) {
    if (row.kind === 'spending' && Math.floor(row.day / 100) === month) {
      totals.set(row.categoryID, (totals.get(row.categoryID) ?? 0) + row.amount);
    }
  }
  return totals;
}

export function deleteCategory(settings: ExpenseSettings, id: string): ExpenseSettings {
  return {
    ...settings,
    categories: settings.categories.filter((category) => category.id !== id),
    rules: Object.fromEntries(Object.entries(settings.rules).filter(([, categoryID]) => categoryID !== id)),
    overrides: Object.fromEntries(Object.entries(settings.overrides).filter(([, override]) => override.category?._0 !== id)),
    manual: settings.manual.map((row) => row.categoryID === id ? { ...row, categoryID: undefined } : row),
  };
}

export function suggestLimits(settings: ExpenseSettings, rows: Expense[], current: MonthKey) {
  const history = new Set([1, 2, 3].map((offset) => moveMonth(current, -offset)));
  const spending = rows.filter((row) => row.kind === 'spending' && history.has(Math.floor(row.day / 100)));
  const months = new Set(spending.map((row) => Math.floor(row.day / 100))).size;
  if (!months) return { settings, count: 0, months: 0 };
  let count = 0;
  const categories = settings.categories.map((category) => {
    const total = spending.filter((row) => row.categoryID === category.id).reduce((sum, row) => sum + row.amount, 0);
    if (total <= 0) return category;
    count += 1;
    return { ...category, limit: Math.ceil(total / months * 1.1 / 10) * 10 };
  });
  return { settings: { ...settings, categories, totalLimit: categories.reduce((sum, category) => sum + (category.limit ?? 0), 0) }, count, months };
}

export function limitStatus(spent: number, limit: number | undefined, alertAt: number) {
  if (!limit) return 'none';
  return spent > limit ? 'over' : spent >= limit * alertAt ? 'warning' : 'within';
}

/** Empty disables a limit; malformed input stays visible for correction. */
export function parseAmount(text: string): number | undefined | 'invalid' {
  const trimmed = text.trim();
  if (!trimmed) return undefined;
  if (!/^(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$/.test(trimmed)) return 'invalid';
  const value = Number(trimmed.replaceAll('.', '').replace(',', '.'));
  return Number.isFinite(value) && value > 0 ? value : 'invalid';
}

export function newCategory(name: string): ExpenseCategory {
  const id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (letter) => {
    const value = Math.floor(Math.random() * 16);
    return (letter === 'x' ? value : (value & 3) | 8).toString(16);
  });
  return { id, name, symbol: 'tag', pluggyKeywords: [] };
}

/** Same merchant rules and per-row choices as the desktop, applied immutably. */
export function setExpenseCategory(settings: ExpenseSettings, row: Expense, id?: string, forStore = false, rows: Expense[] = []): ExpenseSettings {
  const overrides = { ...settings.overrides };
  if (id) overrides[row.id] = { category: { _0: id } };
  else delete overrides[row.id];
  if (id && forStore) {
    // Only explicit category choices are cleared; exclusions and deletions survive.
    for (const other of rows) {
      if (other.id !== row.id && other.merchantKey === row.merchantKey && overrides[other.id]?.category) delete overrides[other.id];
    }
  }
  return { ...settings, overrides, rules: id && forStore ? { ...settings.rules, [row.merchantKey]: id } : settings.rules };
}

export function removeExpense(settings: ExpenseSettings, row: Expense): ExpenseSettings {
  const overrides = { ...settings.overrides };
  if (row.isManual) delete overrides[row.id];
  else overrides[row.id] = { deleted: {} };
  return { ...settings, overrides, manual: settings.manual.filter((entry) => entry.id !== row.id) };
}

export function setExpenseOutside(settings: ExpenseSettings, row: Expense, outside: boolean): ExpenseSettings {
  const overrides = { ...settings.overrides };
  if (outside) overrides[row.id] = { outside: {} };
  else delete overrides[row.id];
  return { ...settings, overrides };
}
