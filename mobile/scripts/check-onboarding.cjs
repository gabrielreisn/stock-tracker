const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const defaults = require('../src/data/default-categories.json');
const source = fs.readFileSync(path.join(__dirname, '../src/lib/onboarding.ts'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true },
}).outputText;
const saved = new Map();
function launch() {
  const exports = {};
  vm.runInNewContext(compiled, { exports, require(name) {
    if (name === 'expo-sqlite/kv-store') return {
      getItemSync: key => saved.get(key) ?? null,
      setItemSync: (key, value) => saved.set(key, value),
    };
    if (name === '@/data/default-categories.json') return defaults;
    throw new Error(name);
  } });
  return exports;
}
let guide = launch();
assert.equal(guide.shouldShowOnboarding(), true, 'fresh installation');
guide.markOnboardingSeen(); // User quits before finishing; marker is already persisted.
assert.equal(launch().shouldShowOnboarding(), false, 'restart after interrupted setup');
assert.equal(launch().shouldShowOnboarding(), false, 'new JS bundle / app update');
for (const key of ['personal-account-v1', 'pluggyClientId', 'pluggyItems', 'pluggy-cache-v1', 'benchmarks']) {
  saved.clear();
  saved.set(key, '{}');
  guide = launch();
  assert.equal(guide.shouldShowOnboarding(), false, `existing installation: ${key}`);
  guide.markOnboardingSeen();
  saved.delete(key);
  assert.equal(launch().shouldShowOnboarding(), false, 'clearing credentials/data does not reopen setup');
}
saved.clear();
assert.equal(launch().shouldShowOnboarding(), true, 'new installation without restored data');
const settings = { categories: structuredClone(defaults), rules: { cafe: defaults[0].id },
  overrides: { one: { category: { _0: defaults[0].id } }, two: { outside: {} } },
  manual: [{ id: 'manual', categoryID: defaults[0].id }], totalLimit: 1000 };
guide = launch();
assert.equal(guide.adoptOnboardingCategories(settings, new Set()), settings, 'empty selection retains defaults');
const picked = new Set(['onboarding-car', defaults.find(row => row.symbol === 'car').id]);
const result = guide.adoptOnboardingCategories(settings, picked);
assert.equal(result.categories.length, 2);
assert.equal(result.categories[0].name, 'Car', 'fuel category precedes general transport');
assert.equal(result.totalLimit, 1000);
assert.equal(Object.keys(result.rules).length, 0);
assert.equal(Object.keys(result.overrides).length, 1);
assert.equal(result.manual[0].categoryID, undefined);
const custom = { ...settings, categories: [{ ...defaults[0], monthlyLimit: 200 }] };
const merged = guide.adoptOnboardingCategories(custom, picked);
assert.equal(merged.categories[0], custom.categories[0], 'existing category and limit survive');
assert.equal(merged.categories.length, 3);
assert.equal(guide.adoptOnboardingCategories(merged, picked).categories.length, 3, 'no duplicates');
console.log('Onboarding checks passed: first launch, interrupted setup, upgrades, legacy data, reinstall and category adoption.');
