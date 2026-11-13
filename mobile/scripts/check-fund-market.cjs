const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const fflate = require('fflate');
const modules = {};
const storage = new Map();
let responseMode = 'ok',
  requests = 0;
const fif =
  'CNPJ_FUNDO_CLASSE;ID_SUBCLASSE;DT_COMPTC;VL_QUOTA\n12.345.678/0001-90;;2025-10-31;1\n12.345.678/0001-90;;2025-12-31;1.1\n12.345.678/0001-90;;2026-09-30;1.2\n12.345.678/0001-90;;2026-10-30;1.3\n12.345.678/0001-90;SUBCLASS;2026-10-30;999\n99.999.999/0001-99;;2026-10-30;999\n';
const fidc =
  'CNPJ_FUNDO_CLASSE;DT_COMPTC;TAB_X_QT_COTA;TAB_X_VL_COTA\n12.345.678/0001-90;2026-09-30;10;2\n12.345.678/0001-90;2026-09-30;20;3\n12.345.678/0001-90;2026-09-30;5;4';
function load(name) {
  if (modules[name]) return modules[name];
  const api = (modules[name] = {});
  const source = fs.readFileSync(`src/lib/${name}.ts`, 'utf8');
  vm.runInNewContext(
    ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS },
    }).outputText,
    {
      exports: api,
      console,
      setTimeout,
      clearTimeout,
      AbortController,
      fetch: async (url) => {
        requests++;
        if (responseMode === 'fail') throw new Error('offline');
        if (responseMode === '404') return { status: 404 };
        const month = url.match(/(\d{6})\.zip$/)[1];
        const bytes = fflate.zipSync({
          [`inf_diario_fi_${month}.csv`]: fflate.strToU8(fif),
        });
        return { status: 200, ok: true, arrayBuffer: async () => bytes.buffer };
      },
      require(id) {
        if (id === 'fflate') return fflate;
        if (id === 'react') return { useEffect() {} };
        if (id === 'expo-sqlite/kv-store')
          return {
            default: {
              getItemSync: (key) => storage.get(key),
              setItemSync: (key, value) => storage.set(key, value),
            },
          };
        if (id === '@/lib/external-store')
          return {
            createStore(initial) {
              let state = initial;
              return {
                get: () => state,
                set: (patch) => {
                  state = { ...state, ...patch };
                },
                useValue: () => state,
              };
            },
          };
        if (id.startsWith('@/lib/')) return load(id.slice(6));
        throw new Error(id);
      },
    },
  );
  return api;
}
// Main cases below use explicit calendar boundaries (Oct 30 -> Sep 30, Oct 30 last year).
async function verify() {
  const api = load('cvm-funds'),
    perf = load('fund-performance');
  const id = '12345678000190',
    ids = new Set([id]);
  const parser = api.createQuotaParser('fif', ids);
  for (let i = 0; i < fif.length; i += 11)
    parser.push(fif.slice(i, i + 11), i + 11 >= fif.length);
  const history = parser.result()[id];
  assert.deepEqual(Array.from(history.prices), [1, 1.1, 1.2, 1.3]);
  const monthly = api.createQuotaParser('fidc', ids);
  monthly.push(fidc, true);
  assert.equal(monthly.result()[id].prices[0], 3);
  const legacy = api.createQuotaParser('fif', ids);
  legacy.push(
    'CNPJ_FUNDO;DT_COMPTC;VL_QUOTA\n12.345.678/0001-90;2024-01-31;2',
    true,
  );
  assert.equal(legacy.result()[id].prices[0], 2);
  const result = perf.fundReturns(history);
  assert.ok(Math.abs(result.month - (1.3 / 1.2 - 1)) < 1e-10);
  assert.ok(Math.abs(result.ytd - (1.3 / 1.1 - 1)) < 1e-10);
  assert.equal(
    result.year,
    undefined,
    'Do not invent a base before the first quote',
  );
  const complete = {
    days: [20251030, ...history.days],
    prices: [0.9, ...history.prices],
  };
  assert.ok(
    Math.abs(perf.fundReturns(complete).year - (1.3 / 0.9 - 1)) < 1e-10,
  );
  const leap = perf.fundReturns({
    days: [20230228, 20240129, 20240229],
    prices: [1, 2, 3],
  });
  assert.equal(leap.year, 2);
  assert.equal(leap.month, 0.5);
  const fund = {
    id,
    cnpj: id,
    kind: 'fif',
    quantity: 10,
    statementPrice: 5,
    statementDay: 20261109,
    statementFromOpenFinance: true,
  };
  const value = perf.fundValuation(fund, complete);
  assert.equal(value.gross, 50);
  assert.equal(value.source, 'Open Finance');
  assert.equal(value.returnDay, 20261030);
  assert.equal(
    value.year,
    perf.fundReturns(complete).year,
    'Newer statement does not change CVM performance',
  );
  assert.equal(
    perf.fundValuation({ ...fund, statementDay: 20261030 }, complete).source,
    'CVM daily',
    'CVM wins ties',
  );
  assert.equal(perf.fundValuation({ ...fund, kind: 'fip' }).year, undefined);
  assert.equal(
    perf.weightedFundReturn(
      [
        undefined,
        { gross: 100 },
        { gross: 50, month: 0.1 },
        { gross: 150, month: -0.1 },
      ],
      'month',
    ),
    -0.05,
  );
  const compressed = fflate.zipSync({
    'irrelevant.csv': fflate.strToU8('skip me'),
    'inf_diario_fi_202610.csv': fflate.strToU8(fif),
  });
  assert.equal(
    (await api.parseQuotaArchive(compressed, 'fif', 202610, ids))[id].prices.at(
      -1,
    ),
    1.3,
  );
  const market = load('use-fund-market');
  await market.refreshFundMarket([fund]);
  const count = requests;
  await market.refreshFundMarket([fund]);
  assert.equal(requests, count, 'Fresh report cache avoids redownload');
  await market.refreshFundMarket([fund], true);
  assert.ok(requests > count, 'Pull forces a real reload');
  responseMode = 'fail';
  await market.refreshFundMarket([fund], true);
  const state = market.useFundMarket([fund]);
  assert.equal(state.loading, false);
  assert.ok(state.failed.length > 0);
  assert.ok(
    state.histories[id].days.length > 0,
    'Offline refresh preserves cached histories',
  );
  const beforeFip = requests;
  await market.refreshFundMarket([{ ...fund, kind: 'fip' }], true);
  assert.equal(requests, beforeFip);
  responseMode = '404';
  assert.equal(
    Object.keys(await api.fetchQuotaReport('fif', 202611, ids)).length,
    0,
  );
  for (const [path, kind, month, cnpj] of [
    ['/tmp/funds-fi-sample.zip', 'fif', 202610, '36352361000144'],
    ['/tmp/funds-fidc-sample.zip', 'fidc', 202609, '42934790000122'],
  ])
    if (process.argv.includes('--live') && fs.existsSync(path)) {
      const rows = await api.parseQuotaArchive(
        new Uint8Array(fs.readFileSync(path)),
        kind,
        month,
        new Set([cnpj]),
      );
      assert.ok(
        rows[cnpj]?.days.length > 0,
        `Actual CVM ${kind} contains screenshot holding`,
      );
      const periods =
        kind === 'fif' ? [202510, 202512, 202609] : [202509, 202512, 202608];
      const sources = [rows];
      for (const period of periods) {
        const baselineFile = `/tmp/funds-live-${kind}-${period}.zip`;
        if (fs.existsSync(baselineFile))
          sources.push(
            await api.parseQuotaArchive(
              new Uint8Array(fs.readFileSync(baselineFile)),
              kind,
              period,
              new Set([cnpj]),
            ),
          );
      }
      if (sources.length === 4) {
        const returns = perf.fundReturns(
          api.mergeFundHistories(...sources)[cnpj],
        );
        for (const period of ['month', 'ytd', 'year'])
          assert.ok(
            Number.isFinite(returns[period]),
            `Actual ${kind} ${period} return`,
          );
        console.log(
          `Actual ${kind} returns: 1M ${perf.signedPercent(returns.month)}, YTD ${perf.signedPercent(returns.ytd)}, 12M ${perf.signedPercent(returns.year)}`,
        );
      }
      console.log(
        `Actual CVM ${kind}: ${cnpj}, ${rows[cnpj].days.length} quotes, latest ${rows[cnpj].prices.at(-1)}`,
      );
    }
  console.log(
    'Fund market checks passed: streamed FIF/FIDC parsing, return periods, leap dates, sources, weighting, refresh, cache and failures.',
  );
}
verify().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
