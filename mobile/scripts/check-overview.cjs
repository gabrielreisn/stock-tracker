const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const modules = {};
function load(name) {
  if (modules[name]) return modules[name].exports;
  const module = { exports: {} };
  modules[name] = module;
  const source = fs.readFileSync(path.join(process.cwd(), 'src/lib', `${name}.ts`), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  new Function('exports', 'require', 'module', code)(module.exports, id => id.startsWith('@/lib/') ? load(id.slice(6)) : require(id), module);
  return module.exports;
}
const o = load('overview');
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-8, `${a} != ${b}`);
assert.deepEqual(o.stockQuantities([{ ticker: 'X', kind: 'buy', quantity: 10 }, { ticker: 'X', kind: 'sell', quantity: 3 }, { ticker: 'Y', kind: 'sell', quantity: 1 }]), [['X', 7]]);
assert.equal(o.priceOn({ days: [20250102, 20250106], prices: [10, 12] }, 20250101), undefined);
assert.equal(o.priceOn({ days: [20250102, 20250106], prices: [10, 12] }, 20250105), 10);
assert.equal(o.rangeStart('3M', 20250531, 20200101), 20250228);
assert.equal(o.rangeStart('1Y', 20240229, 20200101), 20230228);
assert.equal(o.rangeStart('YTD', 20261109, 20200101), 20260101);
const days = [20250102, 20250103, 20250106];
const curves = o.chainReturns(days, [{ assetClass: 'stocks', values: [100, 110, 121] }, { assetClass: 'bonds', values: [undefined, 200, 220] }]);
close(curves.at(-1).value, 1.21); // Entry adds no fictitious investment return.
close(o.rebase(curves, 20250106)[0].value, .1);
assert.deepEqual(o.chainReturns(days, [{ assetClass: 'funds', values: [undefined, undefined, undefined] }]), []);
const stock = { id: 'trade', ticker: 'AAPL', quantity: 2, kind: 'buy', date: '2024-01-01T00:00:00Z', price: 999 };
const history = { days, prices: [10, 11, 12] };
const market = { stocks: { AAPL: history }, fx: { days, prices: [5, 5, 6] }, funds: {}, rates: null };
const fund = { id: 'fund', cnpj: '12345678000190', name: 'Fund', kind: 'fip', quantity: 3, taxExempt: true, statementPrice: 10, statementDay: 20250103 };
const result = o.buildOverview([stock], [], [fund], market, 20250106);
close(result.curve.at(-1).value, 1.44); // Statement-only funds do not enter returns.
assert.equal(result.total, 174); // Adjusted close × quantity × FX + statement value.
assert.equal(result.missing, 0);
assert.equal(result.slices.find(slice => slice.label === 'Stocks US').value, 144);
assert.equal(result.positions[0].name, 'AAPL');
const missing = o.buildOverview([stock], [], [{ ...fund, statementPrice: undefined }], o.emptyMarket, 20250106);
assert.equal(missing.missing, 2);
assert.equal(missing.total, 0);
assert.deepEqual(missing.curve, []);
assert.equal(o.buildOverview([], [], [{ ...fund, statementDay: 20250107 }], o.emptyMarket, 20250106).missing, 1);
const fixture = name => JSON.parse(fs.readFileSync(`src/data/demo/${name}.json`, 'utf8'));
console.time('demo overview');
const demo = o.buildOverview(fixture('trades'), fixture('bonds'), fixture('fund-holdings'), o.emptyMarket, 20261109);
console.timeEnd('demo overview');
assert.equal(demo.positions.filter(position => position.assetClass === 'stocks').length, 14);
assert.equal(demo.positions.filter(position => position.assetClass === 'bonds').length, 6);
assert.equal(demo.positions.filter(position => position.assetClass === 'funds').length, 5);
assert.equal(demo.missing, 23);
assert.ok(demo.total > 60000);
assert.equal(demo.values.funds, 0);
console.log('Overview checks passed: aggregation, FX, missing prices, statement dates, weighting and ranges.');
const rates = { cdi: [{ day: 20250102, rate: 1 }, { day: 20250103, rate: 2 }], ipca: [{ day: 20250101, rate: 3.1 }] };
assert.deepEqual(o.rateBenchmarkLevels([20250102, 20250103, 20250106], rates, 'cdi').map(point => point.value), [1, 1.01, 1.0302]);
close(o.rateBenchmarkLevels([20250116], rates, 'ipca')[0].value, 1.031 ** (15 / 31));
close(o.rateBenchmarkLevels([20250201], rates, 'ipca')[0].value, 1.031);
assert.deepEqual(o.rateBenchmarkLevels(days, { cdi: [], ipca: [] }, 'cdi'), []);
console.log('Benchmark checks passed: CDI timing, monthly IPCA and missing rates.');

const weighted = o.chainReturns(days, [{ assetClass: 'stocks', values: [100, 110, 121] }, { assetClass: 'bonds', values: [undefined, 200, 200] }]);
close(weighted.at(-1).value, 1.1 * 321 / 310);
close(result.slices.reduce((sum, slice) => sum + slice.value, 0), result.total);
