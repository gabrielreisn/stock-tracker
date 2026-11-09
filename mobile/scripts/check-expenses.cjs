const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const ts = require('typescript');

function load(file) {
  const entry = path.resolve(__dirname, '..', file);
  const output = ts.transpileModule(fs.readFileSync(entry, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
  }).outputText;
  const exports = {};
  vm.runInNewContext(output, { exports, require: createRequire(entry) }, { filename: entry });
  return exports;
}
const { createDemoData } = load('src/data/demo/index.ts');
const { classifyExpenses, spendingByCategory, deleteCategory, suggestLimits, limitStatus, parseAmount, setExpenseCategory, setExpenseOutside, removeExpense } = load('src/lib/expenses.ts');
const demo = createDemoData(20261109);
const rows = classifyExpenses(demo.transactions, demo.expenses);
assert.ok(rows.some((row) => row.kind === 'spending' && row.isCard));
assert.ok(rows.some((row) => row.kind === 'spending' && !row.isCard));
assert.ok(rows.some((row) => row.kind === 'income'));
assert.ok(rows.filter((row) => row.detail.includes('PAGAMENTO FATURA')).every((row) => row.kind === 'outside'));
const november = spendingByCategory(rows, 202611);
assert.ok([...november.values()].reduce((sum, amount) => sum + amount, 0) > 0);
assert.ok(rows.filter((row) => Math.floor(row.day / 100) === 202611).every((row) => row.day <= 20261109));

// Sign is not direction: exclude positive credits and count both debit conventions.
const category = demo.expenses.categories[0];
const bank = demo.transactions.accounts.find((account) => account.type === 'BANK').id;
const card = demo.transactions.accounts.find((account) => account.type === 'CREDIT').id;
const make = (id, accountId, type, amount, extra = {}) => ({ id, accountId, type, amount,
  date: '2026-11-02T15:00:00Z', category: 'Groceries', description: 'TEST', ...extra });
const cache = { accounts: demo.transactions.accounts, months: { 202611: [
  make('bank-debit', bank, 'DEBIT', -30), make('card-debit', card, 'DEBIT', 40),
  make('salary', bank, 'CREDIT', 500), make('refund', card, 'CREDIT', -15),
  make('bill', bank, 'DEBIT', -40, { category: 'Credit card payment' }),
  make('foreign', card, 'DEBIT', 100, { currencyCode: 'USD', amountInAccountCurrency: 510 }),
  make('missing-rate', card, 'DEBIT', 200, { currencyCode: 'USD' }),
  make('installment', card, 'DEBIT', 50, { creditCardMetadata: { installmentNumber: 2, totalInstallments: 3, purchaseDate: '2026-10-10T15:00:00Z' } }),
] } };
const classified = classifyExpenses(cache, demo.expenses);
assert.equal(classified.find((row) => row.id === 'refund').kind, 'outside');
assert.equal(classified.find((row) => row.id === 'salary').kind, 'income');
assert.equal(classified.find((row) => row.id === 'installment').day, 20261101);
assert.equal(classified.find((row) => row.id === 'missing-rate').amount, 0);
assert.equal(spendingByCategory(classified, 202611).get(category.id), 630);

// Rules beat keywords; explicit overrides beat rules, and deleted rows stay excluded.
const second = demo.expenses.categories[1];
const settings = { ...demo.expenses, rules: { TEST: second.id }, overrides: {
  'bank-debit': { category: { _0: category.id } }, salary: { deleted: {} },
}, manual: [{ id: 'manual', day: 20261103, store: 'Cash', amount: 12, categoryID: category.id }] };
const overridden = classifyExpenses(cache, settings);
assert.equal(overridden.find((row) => row.id === 'bank-debit').categoryID, category.id);
assert.equal(overridden.find((row) => row.id === 'card-debit').categoryID, second.id);
assert.ok(!overridden.some((row) => row.id === 'salary'));
const removed = deleteCategory(settings, category.id);
assert.ok(!removed.categories.some((item) => item.id === category.id));
assert.equal(removed.overrides['bank-debit'], undefined);
assert.equal(removed.manual[0].categoryID, undefined);
assert.equal(spendingByCategory(classifyExpenses(cache, removed), 202611).get(undefined), 12);
const removedRule = deleteCategory(settings, second.id);
assert.equal(removedRule.rules.TEST, undefined);

const suggestion = suggestLimits(demo.expenses, rows, 202611);
assert.equal(suggestion.months, 3);
assert.ok(suggestion.count > 0);
const total = rows.filter((row) => row.kind === 'spending' && row.categoryID === category.id && [202608, 202609, 202610].includes(Math.floor(row.day / 100)))
  .reduce((sum, row) => sum + row.amount, 0);
assert.equal(suggestion.settings.categories[0].limit, Math.ceil(total / 3 * 1.1 / 10) * 10);
assert.equal(suggestion.settings.totalLimit, suggestion.settings.categories.reduce((sum, item) => sum + (item.limit ?? 0), 0));
assert.equal(suggestLimits(demo.expenses, [], 202611).months, 0);
assert.equal(limitStatus(79, 100, 0.8), 'within');
assert.equal(limitStatus(80, 100, 0.8), 'warning');
assert.equal(limitStatus(100, 100, 0.8), 'warning');
assert.equal(limitStatus(101, 100, 0.8), 'over');
assert.equal(limitStatus(101, undefined, 0.8), 'none');
assert.equal(parseAmount('1.234,50'), 1234.5);
assert.equal(parseAmount('1234,5'), 1234.5);
assert.equal(parseAmount(''), undefined);
for (const input of ['-1', '0', 'abc', '12,34,5', 'Infinity', '1.23']) assert.equal(parseAmount(input), 'invalid');
assert.equal(demo.expenses.totalLimit, 11000, 'suggestion must not mutate the fixture');
console.log('Expense classification, suggestions, deletion, thresholds and amount checks passed.');

// Merchant rules apply across months, while excluded/deleted rows stay untouched.
const sameStore = classified.filter((row) => row.merchantKey === 'TEST');
const ruleSettings = { ...settings, overrides: {
  'bank-debit': { category: { _0: category.id } },
  'card-debit': { category: { _0: category.id } },
  bill: { outside: {} }, salary: { deleted: {} },
} };
const before = JSON.stringify(ruleSettings);
const updated = setExpenseCategory(ruleSettings, sameStore[0], second.id, true, classified);
assert.equal(updated.rules.TEST, second.id);
assert.equal(updated.overrides['card-debit'], undefined);
assert.ok(updated.overrides.bill.outside);
assert.ok(updated.overrides.salary.deleted);
assert.equal(JSON.stringify(ruleSettings), before, 'category edits must not mutate the store snapshot');
const automatic = setExpenseCategory(updated, sameStore[0]);
assert.equal(automatic.overrides[sameStore[0].id], undefined);
const excluded = setExpenseOutside(updated, sameStore[0], true);
assert.equal(classifyExpenses(cache, excluded).find((row) => row.id === sameStore[0].id).kind, 'outside');
assert.equal(setExpenseOutside(excluded, sameStore[0], false).overrides[sameStore[0].id], undefined);
const deleted = removeExpense(updated, sameStore[0]);
assert.ok(!classifyExpenses(cache, deleted).some((row) => row.id === sameStore[0].id));
const manualRow = overridden.find((row) => row.id === 'manual');
const manualDeleted = removeExpense(settings, manualRow);
assert.equal(manualDeleted.manual.length, 0);
assert.equal(manualDeleted.overrides.manual, undefined);
const sourceCache = { ...cache, months: { 202611: [
  make('pix', bank, 'DEBIT', -10, { paymentData: { paymentMethod: 'PIX' } }),
  make('debit', bank, 'DEBIT', -10, { description: 'Compra débito' }),
  make('auto', bank, 'DEBIT', -10, { description: 'Débito automático' }),
  make('boleto', bank, 'DEBIT', -10, { paymentData: { paymentMethod: 'BOLETO' } }),
  make('transfer', bank, 'DEBIT', -10, { paymentData: { paymentMethod: 'TED' } }),
] } };
assert.equal(classifyExpenses(sourceCache, demo.expenses).map((row) => row.source).join(','), 'pix,debitCard,autoDebit,boleto,transfer');
console.log('Expense transaction actions and payment sources passed.');
