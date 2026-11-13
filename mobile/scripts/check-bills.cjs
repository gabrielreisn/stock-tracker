const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const ts = require('typescript');

function load(relative) {
  const file = path.resolve(__dirname, relative);
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const exports = {};
  // Model the app runtime, where these newer Array methods are unavailable.
  const context = vm.createContext({ exports, require: createRequire(file) });
  vm.runInContext('Array.prototype.toSorted = undefined; Array.prototype.toReversed = undefined;', context);
  vm.runInContext(compiled, context, { filename: file });
  return exports;
}
const { createDemoData } = load('../src/data/demo/index.ts');
const { classifyExpenses, recurringBills, upcomingBills, dueDate, daysBetween, billKey, financing, trackablePayments } = load('../src/lib/bills.ts');
const today = 20261109;
const data = createDemoData(today);
const expenses = classifyExpenses(data);
const originalExpenses = JSON.stringify(expenses);
const bills = recurringBills(expenses, {}, today);
assert.equal(JSON.stringify(expenses), originalExpenses, 'recurrence detection preserves input order');
assert.equal(bills.length, 4, 'demo detects utilities and condominium, excluding card payments');
assert.ok(bills.every((b) => b.usual > 0 && !b.lastPayment.isCard));
assert.ok(bills.some((b) => b.name.includes('ENEL')));
assert.ok(!bills.some((b) => b.name.includes('NUBANK')));
const bankCredit = expenses.find((e) => e.detail.includes('SALARIO'));
assert.equal(bankCredit.kind, 'income');
const cardPurchase = expenses.find((e) => e.isCard && e.amount > 0 && e.kind === 'spending');
assert.ok(cardPurchase, 'positive card debits classify as purchases');
assert.equal(expenses.find((e) => e.detail.includes('PAGAMENTO FATURA')).kind, 'outside');
assert.equal(dueDate(31, 202702), 20270228);
assert.equal(dueDate(31, 202802), 20280229);
assert.equal(daysBetween(20261231, 20270101), 1);
assert.equal(financing('Parcela 012 de 360 Crédito Imobiliário').number, 12);
assert.equal(financing('Parcela 13/12'), undefined);

// An unpaid recurring utility: grace period, manual marker, due-day override and hiding.
const utility = bills.find((b) => b.name.includes('VIVO'));
const key = utility.key;
const unpaidRows = expenses.filter((e) => !(billKey(e) === key && Math.floor(e.day / 100) === 202611));
function utilityAt(day, choice = {}) {
  return recurringBills(unpaidRows, { [key]: choice }, day).find((b) => b.key === key);
}
assert.equal(utilityAt(20261113, { dueDay: 10 }).status, 'upcoming');
assert.equal(utilityAt(20261114, { dueDay: 10 }).status, 'late');
const marked = utilityAt(today, { dueDay: 31, paidByHand: [202611] });
assert.equal(marked.status, 'paid');
assert.equal(marked.nextDue, 20261231);
assert.equal(marked.paidThisMonth.length, 0, 'manual markers never invent payments');
assert.notEqual(utilityAt(today, { dueDay: 1 }).status, 'paid', 'undo restores unpaid state');
assert.equal(utilityAt(today, { tracked: false }), undefined);
assert.ok(utilityAt(today), 'restoring automatic detection brings the bill back');
assert.notEqual(utilityAt(20261201, { paidByHand: [202611] }).status, 'paid', 'markers apply only to their month');
const onePayment = unpaidRows.filter((e) => billKey(e) === key).slice(0, 1);
assert.equal(recurringBills(onePayment, {}, today).length, 0);
assert.equal(recurringBills(onePayment, { [key]: { tracked: true } }, today).length, 1);
const originalBills = JSON.stringify(bills);
const upcoming = upcomingBills(bills, today);
const candidates = trackablePayments(expenses, bills, {}, today);
assert.ok(candidates.size > 0, 'tracking picker works without modern Array methods');
assert.equal(JSON.stringify(expenses), originalExpenses, 'tracking picker preserves input order');
assert.equal(JSON.stringify(bills), originalBills, 'upcoming sorting preserves recurring bills');
assert.ok(upcoming.every((b) => b.status === 'late' || daysBetween(today, b.nextDue) <= 30));
assert.equal(upcomingBills([{ ...utility, status: 'paid', nextDue: 20270101 }], today).length, 0);

// Automatic debits remain grouped when merchant names or numeric references change.
const a = { ...utility.lastPayment, source: 'autoDebit', detail: 'Débito automático ENEL 123', merchantKey: 'OLD' };
const b = { ...a, detail: 'Debito automatico ENEL 456', merchantKey: 'NEW' };
assert.equal(billKey(a), billKey(b));
const deleted = createDemoData(today);
const id = utility.lastPayment.id;
deleted.expenses.overrides[id] = { deleted: {} };
assert.ok(!classifyExpenses(deleted).some((e) => e.id === id));
assert.equal(data.expenses.bills?.[key], undefined, 'derivations never mutate demo settings');
console.log('Bills checks passed: demo detection, classification, dates, grace period, manual controls and isolation.');


// Real bank statements: keep account histories together and never infer missed payments.
const { groupCardBills, cardBillPayment } = load('../src/lib/card-bills.ts');
const statements = [
  { id: 'older', accountId: 'card', dueDate: '2026-09-13', totalAmount: 100, payments: [{ amount: -100 }] },
  { id: 'latest', accountId: 'card', dueDate: '2026-10-13', totalAmount: 200, payments: [{ amount: 50 }] },
  { id: 'other', accountId: 'second', dueDate: '2026-10-13', totalAmount: 300 },
];
const snapshot = JSON.stringify(statements);
const groups = groupCardBills(statements, [{ id: 'card', name: 'My card' }]);
assert.equal(groups.length, 2);
assert.equal(groups[0].account.name, 'My card');
assert.equal(groups[0].bills[0].id, 'latest');
assert.equal(JSON.stringify(statements), snapshot, 'presentation grouping preserves cached statements');
assert.equal(cardBillPayment(statements[0]).status, 'paid');
assert.equal(cardBillPayment(statements[1]).remaining, 150);
assert.equal(cardBillPayment(statements[1]).status, 'partial');
assert.equal(cardBillPayment(statements[2]).status, 'unreported');
assert.equal(cardBillPayment(statements[2]).paid, undefined);
assert.equal(cardBillPayment({ id: 'zero', totalAmount: 0 }).status, 'empty');
assert.equal(cardBillPayment({ id: 'unknown', payments: [{ amount: 100 }] }).remaining, undefined);
assert.equal(cardBillPayment({ id: 'missing', totalAmount: 100, payments: [{ amount: null }] }).paid, undefined);
assert.equal(groupCardBills([{ id: 'a' }, { id: 'b' }], []).length, 2);
console.log('Card bill checks passed: grouping, chronology, payment reporting and cache isolation.');
