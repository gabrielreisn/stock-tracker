const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const modules = {};
function load(name) {
  if (modules[name]) return modules[name];
  const source = fs.readFileSync(`src/lib/${name}.ts`, 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} };
  new Function('exports', 'require', 'module', code)(module.exports, id => id.startsWith('@/lib/') ? load(id.slice(6)) : require(id), module);
  return modules[name] = module.exports;
}
const f = load('fgc'), b = load('bonds'), day = 20261109;
const bond = { id: 'one', kind: 'CDB', issuer: 'Bank', issuerCNPJ: '12345678000100', code: 'A', issueDay: day, maturityDay: 20271109, indexer: 'fixed', rate: 12, quantity: 1, unitPrice: 200000 };
const rows = [
  { CodInst: 'C1', NomeInstituicao: 'Group - PRUDENCIAL' },
  { CodInst: '12345678', NomeInstituicao: 'Bank', CodConglomeradoPrudencial: 'C1' },
  { CodInst: '87654321', NomeInstituicao: 'Other Bank', CodConglomeradoPrudencial: 'C1' },
  { CodInst: '11111111', NomeInstituicao: 'Independent' },
];
const groups = f.parseConglomerates(rows);
assert.equal(groups['12345678'].name, 'Group');
assert.deepEqual(groups['87654321'].members, ['Bank', 'Other Bank']);
assert.equal(groups['11111111'], undefined);
const other = { ...bond, id: 'two', issuer: 'Other Bank', issuerCNPJ: '87654321000199', unitPrice: 100000 };
let model = f.buildFGC([bond, other], null, groups, day);
assert.equal(model.exposures.length, 1);
assert.equal(model.guaranteed, 250000);
assert.equal(model.above, 50000);
assert.equal(model.exposures[0].gross, 300000);
assert.ok(model.exposures[0].atMaturity > 300000);
for (const [value, status] of [[null,'unknown'], [200000,'within'], [200001,'near'], [250000,'near'], [250001,'above']]) assert.equal(f.fgcStatus(value), status);
model = f.buildFGC([bond, { ...other, issuerCNPJ: '12.345.678/0002-00' }], null, {}, day);
assert.equal(model.exposures.length, 1);
assert.equal(model.above, 50000);
assert.equal(f.formatCNPJ('12345678000100'), '12.345.678/0001-00');
model = f.buildFGC([{ ...bond, issuer: 'BÁNCO S.A.', issuerCNPJ: undefined }, { ...other, issuer: 'banco sa', issuerCNPJ: 'invalid' }], null, {}, day);
assert.equal(model.exposures.length, 1);
assert.deepEqual(model.exposures[0].cnpjs, []);
for (const kind of ['CDB', 'LC', 'LCI', 'LCA']) assert.equal(f.buildFGC([{ ...bond, kind }], null, {}, day).exposures.length, 1);
for (const kind of ['CRI', 'CRA', 'Debênture', 'Debênture incentivada']) {
  model = f.buildFGC([{ ...bond, kind }], null, {}, day);
  assert.equal(model.exposures.length, 0);
  assert.equal(model.uncovered.length, 1);
}
for (const patch of [{ maturityDay: 20261108 }, { issueDay: 20261110 }]) assert.equal(f.buildFGC([{ ...bond, ...patch }], null, {}, day).exposures.length, 0);
assert.equal(f.buildFGC([{ ...bond, maturityDay: day }], null, {}, day).exposures.length, 1);
model = f.buildFGC([bond, { ...other, indexer: 'cdi' }], null, groups, day);
assert.equal(model.exposures[0].gross, null);
assert.equal(model.exposures[0].atMaturity, null);
assert.equal(model.guaranteed, null);
assert.equal(model.above, null);
const fixtures = require('../src/data/demo/bonds.json');
const rates = { cdi: [{ day: 20240805, rate: .05 }], ipca: [{ day: 20241001, rate: .4 }] };
model = f.buildFGC(fixtures, rates, {}, day);
assert.equal(model.exposures.length, 5);
assert.equal(model.exposures.find(group => group.key === '00416968').bonds.length, 2);
const total = model.exposures.reduce((sum, group) => sum + group.gross, 0);
assert.ok(Math.abs(total - fixtures.reduce((sum, bond) => sum + b.valueBond(bond, rates, day).gross, 0)) < 1e-7);
assert.ok(model.exposures.every((group, i, all) => i === 0 || all[i - 1].gross >= group.gross));
assert.equal(f.buildFGC([], null, {}, day).guaranteed, 0);
// IF.data groups PAN and BTG together; the two Inter holdings also share one limit.
const demoGroups = Object.fromEntries(['30306294', '59285411'].map(root => [root, { code: 'C0080336', name: 'BTG', members: ['BANCO BTG PACTUAL S.A.', 'BANCO PAN S.A.'] }]));
model = f.buildFGC(fixtures, rates, demoGroups, day);
assert.equal(model.exposures.length, 4);
assert.equal(model.exposures.find(group => group.key === 'C0080336').bonds.length, 2);
const large = Array.from({ length: 5 }, (_, i) => ({ ...bond, id: String(i), issuerCNPJ: `1234567${i}000100`, unitPrice: 300000 }));
model = f.buildFGC(large, null, {}, day);
assert.equal(model.guaranteed, 1250000);
assert.equal(model.above, 250000);

async function checkFetch() {
  const original = global.fetch;
  const queried = [];
  try {
    global.fetch = async url => {
      const quarter = Number(new URL(url).searchParams.get('@AnoMes'));
      queried.push(quarter);
      return { ok: true, json: async () => ({ value: quarter === 202609 ? [] : quarter === 202606 ? rows : [{ ...rows[0], NomeInstituicao: 'Old group' }, ...rows.slice(1)] }) };
    };
    const result = await f.fetchConglomerates(new AbortController().signal, day);
    assert.deepEqual(queried, [202609, 202606, 202603]);
    assert.equal(result['12345678'].name, 'Group');
    global.fetch = async () => { throw new Error('offline'); };
    await assert.rejects(f.fetchConglomerates(new AbortController().signal, day), /unavailable/);
    global.fetch = async (_url, { signal }) => { assert.ok(signal.aborted); throw new Error('aborted'); };
    const controller = new AbortController(); controller.abort();
    await assert.rejects(f.fetchConglomerates(controller.signal, day), /unavailable/);
  } finally { global.fetch = original; }
}
checkFetch().then(() => console.log('FGC checks passed: demo totals, grouping, limits, missing values, maturity filtering, API fallback and aborts.')).catch(error => { console.error(error); process.exitCode = 1; });
