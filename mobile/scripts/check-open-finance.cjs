const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const root = path.resolve(__dirname, '../src');
const id = '11111111-1111-4111-8111-111111111111';
const storage = new Map([['pluggyClientId', 'client'], ['pluggyItems', JSON.stringify([id])]]);
const requests = [];
let failInvestment = false;
let withdrawn = false;
let omitBondTerms = false;
let blockItem;
let coreRows = [
  { id: 's1', type: 'EQUITY', code: 'PETR4', quantity: 10, amountOriginal: 200, balance: 300 },
  { id: 's2', type: 'EQUITY', code: 'PETR4', quantity: 5, amountOriginal: 200, balance: 210 },
  { id: 'b1', type: 'FIXED_INCOME', subtype: 'CDB', code: 'CDB-123', quantity: 2, amountOriginal: 2000,
    balance: 2200, issueDate: '2025-01-10', dueDate: '2028-01-10', rateType: 'CDI', rate: 100, fixedAnnualRate: 1.5 },
  { id: 'f1', type: 'MUTUAL_FUND', code: '12.345.678/0001-90', name: 'A FIDC', quantity: 10, amount: 200, value: 20, date: '2026-11-09' },
  { id: 'unsupported', type: 'COE', quantity: 1, amount: 100 },
];

async function fetchMock(input) {
  const url = new URL(input);
  requests.push(url);
  let body;
  let ok = true;
  if (url.pathname === '/auth') body = { apiKey: 'test-key' };
  else if (url.pathname.startsWith('/items/')) {
    if (blockItem) await blockItem;
    body = { id, status: 'UPDATED' };
  } else if (url.pathname === '/accounts') body = { results: [{ id: 'bank', type: 'BANK', name: 'Bank' }, { id: 'card', type: 'CREDIT', name: 'Card' }], totalPages: 1 };
  else if (url.pathname === '/investments') {
    ok = !failInvestment;
    body = ok ? { results: withdrawn ? [] : coreRows.map(row => omitBondTerms && row.id === 'b1'
      ? { ...row, issueDate: null, amountOriginal: null } : row), totalPages: 1 } : { message: 'Offline' };
  } else if (url.pathname === '/v2/transactions') {
    const accountId = url.searchParams.get('accountId');
    body = { results: [{ id: 'tx-' + accountId, amount: -50, type: 'DEBIT', date: '2026-11-02T12:00:00Z', description: 'Test' }], next: null };
  } else if (url.pathname === '/bills') body = { results: [{ id: 'bill', totalAmount: 50, dueDate: '2026-12-01' }], totalPages: 1 };
  else if (url.pathname === '/loans') body = { results: [{ id: 'loan', productName: 'Loan' }], totalPages: 1 };
  else throw new Error('Unexpected endpoint ' + url.pathname);
  return { ok, status: ok ? 200 : 500, text: async () => JSON.stringify(body) };
}

function runtime() {
  const modules = new Map();
  function load(file) {
    file = path.resolve(file);
    if (!path.extname(file)) file += '.ts';
    if (modules.has(file)) return modules.get(file);
    if (file.endsWith('.json')) return JSON.parse(fs.readFileSync(file, 'utf8'));
    const exported = {};
    modules.set(file, exported);
    const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, esModuleInterop: true },
    }).outputText;
    vm.runInNewContext(code, {
      exports: exported, URL, URLSearchParams, AbortController, Date, setTimeout, clearTimeout,
      fetch: fetchMock,
      require(name) {
        if (name === 'react') return { useSyncExternalStore: (_subscribe, snapshot) => snapshot() };
        if (name === 'expo-sqlite/kv-store') return { getItemSync: key => storage.get(key) ?? null,
          setItemSync: (key, value) => storage.set(key, value), removeItemSync: key => storage.delete(key) };
        if (name === 'expo-secure-store') return { getItem: () => 'secret', setItemAsync: async () => {}, deleteItemAsync: async () => {} };
        if (name.endsWith('/i18n')) return { t: key => key };
        return load(name.startsWith('@/') ? path.join(root, name.slice(2)) : path.resolve(path.dirname(file), name));
      },
    }, { filename: file });
    return exported;
  }
  return { pluggy: load(path.join(root, 'lib/pluggy-store.ts')), account: load(path.join(root, 'lib/account-store.ts')),
    mapping: load(path.join(root, 'lib/open-finance.ts')) };
}

async function main() {
  let app = runtime();
  assert.equal(app.account.accountStore.get().data.trades.length, 0, 'Personal account never seeds demo holdings');
  const first = app.pluggy.sync();
  assert.equal(app.pluggy.sync(), first, 'Concurrent callers share the same sync');
  assert.equal(await first, true);
  let data = app.account.accountStore.get().data;
  assert.equal(data.trades.length, 1);
  assert.equal(data.trades[0].quantity, 15);
  assert.ok(Math.abs(data.trades[0].price - 400 / 15) < 1e-9);
  assert.equal(data.bonds[0].indexer, 'cdiPlus');
  assert.equal(data.bonds[0].rate, 1.5);
  assert.equal(data.fundHoldings[0].cnpj, '12345678000190');
  assert.equal(data.fundHoldings[0].statementPrice, 20);
  assert.equal(data.cardBills.length, 1);
  assert.equal(data.loans.length, 1);
  assert.equal(Object.values(data.transactions.months).flat().length, 2);
  assert.equal(app.pluggy.usePluggy().investments.length, 5, 'Unsupported positions remain available for review');
  assert.ok(storage.has('personal-account-v1'));
  assert.ok(!storage.get('personal-account-v1').includes('secret'));
  const settings = { ...data.expenses, totalLimit: 1234 };
  app.account.expenseStore.set({ settings });
  const count = requests.length;
  app = runtime();
  assert.equal(app.account.accountStore.get().data.expenses.totalLimit, 1234);
  assert.equal(app.pluggy.usePluggy().accounts.length, 2);
  await app.pluggy.syncIfNeeded();
  assert.equal(requests.length, count, 'Fresh data survives a process restart without a new request');
  assert.equal(app.mapping.syncIsDue(new Date(0), 6 * 60 * 60_000 - 1), false);
  assert.equal(app.mapping.syncIsDue(new Date(0), 6 * 60 * 60_000), true);

  omitBondTerms = true;
  await app.pluggy.sync();
  assert.equal(app.account.accountStore.get().data.bonds.length, 1, 'Incomplete reported terms preserve a tracked bond');
  omitBondTerms = false;
  failInvestment = true;
  await app.pluggy.sync();
  assert.equal(app.account.accountStore.get().data.trades[0].quantity, 15, 'Failed institutions retain their holdings');
  failInvestment = false;
  withdrawn = true;
  await app.pluggy.sync();
  assert.equal(app.account.accountStore.get().data.trades.length, 0, 'A fully updated empty position list removes imported holdings');
  assert.equal(app.account.accountStore.get().data.expenses.totalLimit, 1234);

  withdrawn = false;
  let release;
  blockItem = new Promise(resolve => { release = resolve; });
  const pending = app.pluggy.sync();
  await new Promise(resolve => setTimeout(resolve, 5));
  app.pluggy.removeItem(id);
  release();
  assert.equal(await pending, false, 'Removing a connection invalidates its in-flight response');
  assert.equal(app.pluggy.usePluggy().investments.length, 0);
  console.log('Open Finance checks passed: empty migration, mapping, persistence, six-hour freshness, partial failures, redemption and removal races.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
