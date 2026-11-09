const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const ts = require('typescript');

const root = path.resolve(__dirname, '..');
const folder = path.join(root, 'src/data/demo');
const files = {
  trades: 'trades', bonds: 'bonds', fundHoldings: 'fund-holdings',
  alerts: 'alerts', expenses: 'expenses', transactions: 'transactions-by-month',
};
const values = {};
for (const [key, name] of Object.entries(files)) {
  const mobile = fs.readFileSync(path.join(folder, `${name}.json`), 'utf8');
  const desktop = fs.readFileSync(path.join(root, '../macOS/Resources/Demo', `${name}.json`), 'utf8');
  assert.equal(mobile, desktop, `${name} must match the macOS source`);
  values[key] = JSON.parse(mobile);
}

// Check literal JSON against every contract, including union members. JSON imports widen strings,
// so the loader's type assertion alone cannot catch e.g. a new misspelled bond kind.
const virtualFile = path.join(folder, '__fixture_contract.ts');
const literal = `const seed = ${JSON.stringify(values)} satisfies import('../../types').DemoData;`;
const options = { strict: true, noEmit: true, skipLibCheck: true, types: [], target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.CommonJS, moduleResolution: ts.ModuleResolutionKind.Node10, ignoreDeprecations: '6.0' };
const host = ts.createCompilerHost(options);
const readFile = host.readFile.bind(host);
host.readFile = (file) => file === virtualFile ? literal : readFile(file);
const program = ts.createProgram([virtualFile], options, host);
const diagnostics = ts.getPreEmitDiagnostics(program);
assert.equal(diagnostics.length, 0, ts.formatDiagnosticsWithColorAndContext(diagnostics, {
  getCurrentDirectory: () => root, getCanonicalFileName: (file) => file, getNewLine: () => '\n',
}));

const entry = path.join(folder, 'index.ts');
const compiled = ts.transpileModule(fs.readFileSync(entry, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true, target: ts.ScriptTarget.ES2022 },
}).outputText;
const exportsObject = {};
vm.runInNewContext(compiled, { exports: exportsObject, require: createRequire(entry) }, { filename: entry });
const { createDemoData } = exportsObject;
const baseline = createDemoData(20261031);
assert.equal(JSON.stringify(baseline.transactions.months), JSON.stringify(values.transactions.months));
for (const today of [20261109, 20260228, 20240229, 20270101]) {
  const data = createDemoData(today);
  assert.equal(Object.keys(data.transactions.months).length, 24);
  assert.ok(data.transactions.months[String(Math.floor(today / 100))]);
  const accounts = new Set(data.transactions.accounts.map((account) => account.id));
  for (const [month, rows] of Object.entries(data.transactions.months)) {
    for (const row of rows) {
      assert.ok(accounts.has(row.accountId));
      const date = Number(row.date.slice(0, 10).replaceAll('-', ''));
      assert.ok(date <= today);
      assert.equal(String(Math.floor(date / 100)), month);
      for (const iso of [row.date, row.creditCardMetadata?.purchaseDate].filter(Boolean)) {
        assert.equal(new Date(iso).toISOString().slice(0, 10), iso.slice(0, 10));
      }
    }
  }
  assert.equal(JSON.stringify(data.trades), JSON.stringify(values.trades));
}
const copy = createDemoData(20261109);
copy.trades[0].quantity = -1;
copy.expenses.categories[0].name = 'Changed';
assert.ok(createDemoData(20261109).trades[0].quantity > 0);
assert.notEqual(createDemoData(20261109).expenses.categories[0].name, 'Changed');
for (const invalid of [20260230, 20261301, 20261100, NaN, 20261109.5]) {
  assert.throws(() => createDemoData(invalid), /YYYYMMDD/);
}
console.log('Demo checks passed: source parity, TS contracts, date shifts, account links and independent copies.');
