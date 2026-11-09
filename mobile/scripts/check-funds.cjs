// Exercise the funds model without requiring a native runtime.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const fixtures = require('../src/data/demo/fund-holdings.json');
const original = structuredClone(fixtures);
const source = fs.readFileSync('src/lib/funds.ts', 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS },
}).outputText;
const api = {};
let state = { holdings: structuredClone(fixtures) };
const testStore = { get: () => state, set: patch => { state = { ...state, ...patch }; } };
vm.runInNewContext(compiled, {
  exports: api,
  require(id) {
    if (id === '@/lib/account-store') {
      return { fundStore: testStore };
    }
    throw new Error(`Unexpected dependency: ${id}`);
  },
});
for (const value of [
  '0',
  '-1',
  'NaN',
  'Infinity',
  '1.000,25',
  '1,000.25',
  '',
  '1e6',
])
  assert.equal(api.parseDecimal(value), undefined, value);
assert.equal(api.parseDecimal('123,456789'), 123.456789);
assert.equal(api.parseDecimal('123.456789'), 123.456789);
assert.equal(api.parseDay('2024-02-29'), 20240229);
for (const value of [
  '2023-02-29',
  '2024-04-31',
  '2024-13-01',
  '2999-01-01',
  'bad',
])
  assert.equal(api.parseDay(value), undefined, value);
const fund = api.fundStore.get().holdings[0];
assert.equal(
  api.grossValue(fund),
  undefined,
  'Missing price must not imply zero',
);
assert.equal(api.money(undefined), '—');
api.saveFund({ ...fund, statementPrice: 2.5, statementDay: 20261030 });
assert.equal(
  api.grossValue(api.fundStore.get().holdings[0]),
  fund.quantity * 2.5,
);
assert.equal(api.fundStore.get().holdings.length, fixtures.length);
assert.equal(
  api.fundPurpose({ ...fund, purpose: undefined, name: 'FUNDO INFLAÇÃO' }),
  'inflation',
);
assert.equal(
  api.fundPurpose({ ...fund, purpose: undefined, kind: 'fidc', name: 'FIDC' }),
  'credit',
);
assert.equal(
  api.fundPurpose({ ...fund, purpose: undefined, kind: 'fip', name: 'FIP' }),
  'infrastructure',
);
assert.equal(api.fundPurpose({ ...fund, purpose: 'equities' }), 'equities');
assert.equal(api.formatCNPJ('45278833000157'), '45.278.833/0001-57');
const added = { ...fund, id: 'new-demo-fund', cnpj: '12345678000190' };
api.saveFund(added);
assert.equal(api.fundStore.get().holdings.length, fixtures.length + 1);
api.deleteFund(added.id);
assert.equal(api.fundStore.get().holdings.length, fixtures.length);
assert.deepEqual(fixtures, original, 'Edits must not mutate source fixtures');
console.log(
  'Funds checks passed: missing valuations, decimal/date validation, purpose, CRUD and fixture isolation.',
);
