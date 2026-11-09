const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const ts = require('typescript');

function load(relative) {
  const entry = path.resolve(__dirname, '..', relative);
  const compiled = ts.transpileModule(fs.readFileSync(entry, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const exports = {};
  vm.runInNewContext(compiled, { exports, require: createRequire(entry) }, { filename: entry });
  return exports;
}
const { classifyExpenses, buildYearData, spendingTrend, finishedAverage } = load('src/lib/insights.ts');
const { createDemoData } = load('src/data/demo/index.ts');
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.00001, `${actual} != ${expected}`);

const demo = createDemoData(20261109);
const snapshot = JSON.stringify(demo);
const expenses = classifyExpenses(demo.transactions, demo.expenses);
const year = buildYearData(expenses, demo.expenses, 2026, 202611);
// Independent fixture accounting: only debits, excluding bank card-bill payments.
const source = Object.values(demo.transactions.months).flat().map((row) => {
  const meta = row.creditCardMetadata;
  const date = new Date(row.date);
  if (meta?.installmentNumber > 1 && meta.totalInstallments > 1) {
    date.setUTCDate(1);
    date.setUTCMonth(date.getUTCMonth() + meta.installmentNumber - 1);
  }
  return { ...row, billedMonth: date.getUTCFullYear() * 100 + date.getUTCMonth() + 1 };
}).filter((row) => row.billedMonth >= 202601 && row.billedMonth <= 202611);
const spending = source.filter((row) => row.type === 'DEBIT' && row.category !== 'Credit card payment');
const income = source.filter((row) => row.type === 'CREDIT');
close(year.totalSpent, spending.reduce((sum, row) => sum + Math.abs(row.amount), 0));
close(year.totalIncome, income.reduce((sum, row) => sum + Math.abs(row.amount), 0));
const finishedSpending = spending.filter((row) => row.billedMonth < 202611);
close(year.averageSpent, finishedSpending.reduce((sum, row) => sum + Math.abs(row.amount), 0) / 10);
close(year.rows.reduce((sum, row) => sum + row.total, 0), year.totalSpent);
for (const point of year.series('all')) {
  close(year.rows.reduce((sum, row) => sum + year.amount(row.id, point.month), 0), point.amount);
}
assert.equal(year.months.length, 11);
assert.equal(year.yearMonths.length, 12);
assert.equal(year.lastFinished, 202610);
assert.equal(year.series('all').at(-1).finished, false);
assert.equal(JSON.stringify(demo), snapshot, 'classification must not mutate the demo account');
const oldest = buildYearData(expenses, demo.expenses, 2024, 202611);
assert.equal(oldest.months[0], 202412, 'trim months before the available history');
const empty = buildYearData([], demo.expenses, 2026, 202611);
assert.equal(empty.months.length, 0);
assert.equal(empty.averageSpent, 0);
assert.equal(empty.highestMonth, undefined);
assert.equal(empty.rows.length, 0);

const category = demo.expenses.categories[0].id;
const settings = { categories: demo.expenses.categories, rules: { CAFE: category }, overrides: {}, manual: [], alertAt: 0.8 };
const cache = { months: { 202601: [] }, accounts: [{ id: 'bank', type: 'BANK' }, { id: 'card', type: 'CREDIT' }], fetchedAt: {} };
function transaction(id, extra = {}) {
  return { id, accountId: 'bank', date: '2026-01-02T15:00:00Z', amount: -100, type: 'DEBIT', description: 'Café!', ...extra };
}
cache.months[202601] = [
  transaction('debit'), transaction('purchase', { accountId: 'card', amount: 150 }),
  transaction('income', { type: 'CREDIT', amount: 500 }),
  transaction('bill', { category: 'Credit card payment' }),
  transaction('own', { category: 'Transfer - same ownership' }),
  transaction('investment', { description: 'APLICACAO CDB' }),
  transaction('refund', { accountId: 'card', type: 'CREDIT' }),
  transaction('uncategorized', { description: 'Unknown' }),
  transaction('foreign', { currencyCode: 'USD', amount: 10 }),
  transaction('converted', { currencyCode: 'USD', amount: 10, amountInAccountCurrency: 55 }),
  transaction('installment', { accountId: 'card', creditCardMetadata: { installmentNumber: 2, totalInstallments: 3, purchaseDate: '2025-12-31T15:00:00Z' } }),
];
cache.months[202602] = [cache.months[202601][0]]; // overlap in caches must not double-count
let rows = classifyExpenses(cache, settings);
assert.equal(rows.length, 11);
for (const id of ['bill', 'own', 'investment', 'refund']) assert.equal(rows.find((row) => row.id === id).kind, 'outside');
assert.equal(rows.find((row) => row.id === 'purchase').kind, 'spending');
assert.equal(rows.find((row) => row.id === 'purchase').amount, 150);
assert.equal(rows.find((row) => row.id === 'income').kind, 'income');
assert.equal(rows.find((row) => row.id === 'debit').categoryID, category, 'normalized merchant rules');
assert.equal(rows.find((row) => row.id === 'uncategorized').categoryID, undefined);
assert.equal(rows.find((row) => row.id === 'foreign').amount, 0, 'no invented conversion');
assert.equal(rows.find((row) => row.id === 'converted').amount, 55);
assert.equal(rows.find((row) => row.id === 'installment').day, 20260101);
settings.overrides = { debit: { deleted: {} }, bill: { category: { _0: category } }, purchase: { outside: {} } };
settings.manual = [{ id: 'manual', day: 20260104, store: 'Manual', amount: 12, categoryID: category }];
rows = classifyExpenses(cache, settings);
assert.equal(rows.some((row) => row.id === 'debit'), false);
assert.equal(rows.find((row) => row.id === 'bill').kind, 'spending');
assert.equal(rows.find((row) => row.id === 'purchase').kind, 'outside');
assert.equal(rows.find((row) => row.id === 'manual').amount, 12);
settings.overrides.manual = { deleted: {} };
assert.equal(classifyExpenses(cache, settings).some((row) => row.id === 'manual'), false);

const points = [0, 100, 200, 300, 0].map((amount, index) => ({ month: 202601 + index, amount, finished: index < 4 }));
close(spendingTrend(points).slope, 100);
assert.equal(spendingTrend(points).points.length, 3);
close(finishedAverage(points), 150);
assert.equal(spendingTrend(points.slice(0, 3)), null, 'three finished months after first spending required');
const onlyCurrent = buildYearData([{ ...rows[0], day: 20261101, amount: 50, kind: 'spending' }], settings, 2026, 202611);
assert.equal(onlyCurrent.averageSpent, 50, 'summary falls back to current month if none completed');
assert.equal(finishedAverage(onlyCurrent.series('all')), 0);
assert.equal(spendingTrend(onlyCurrent.series('all')), null);
console.log('Insights checks passed: demo accounting, classifications, overrides, installments, empty years and completed-month trends.');
