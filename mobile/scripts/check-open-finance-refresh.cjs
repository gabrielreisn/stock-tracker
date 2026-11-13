const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const code = ts.transpileModule(fs.readFileSync(path.resolve(__dirname, '../src/lib/pluggy-refresh.ts'), 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
}).outputText;

async function check(native) {
  const calls = [];
  let cleanup;
  let lifecycle;
  let task;
  const background = {
    BackgroundTaskResult: { Success: 1, Failed: 2 }, BackgroundTaskStatus: { Available: 2 },
    getStatusAsync: async () => 2,
    registerTaskAsync: async (name, options) => calls.push(['register', name, options.minimumInterval]),
    unregisterTaskAsync: async () => calls.push(['unregister']),
  };
  const manager = {
    isTaskDefined: () => false,
    defineTask: (name, callback) => { calls.push(['define', name]); task = callback; },
    isTaskRegisteredAsync: async () => false,
  };
  const state = { currentState: 'active', addEventListener: (_, callback) => {
    lifecycle = callback;
    return { remove: () => calls.push(['remove-listener']) };
  } };
  const exported = {};
  vm.runInNewContext(code, {
    exports: exported,
    setInterval: (_, delay) => { calls.push(['timer', delay]); return 1; },
    clearInterval: () => calls.push(['clear-timer']),
    require(name) {
      if (name === '@/lib/expense-notifications') return { notifyCurrentExpenses: async () => calls.push(['notifications']) };
      if (name === 'expo') return { isRunningInExpoGo: () => !native, requireOptionalNativeModule: () => ({}) };
      if (name === 'react') return { useEffect: callback => { cleanup = callback(); } };
      if (name === 'react-native') return { AppState: state };
      if (name === 'expo-task-manager') { assert.ok(native); return manager; }
      if (name === 'expo-background-task') { assert.ok(native); return background; }
      if (name === '@/lib/pluggy-store') return {
        usePluggy: () => ({ itemIDs: ['test-item'] }), isConfigured: () => true,
        prepareBackgroundCredentials: async () => calls.push(['secure-key']),
        syncIfNeeded: async () => { calls.push(['freshness']); return true; },
      };
      throw new Error(name);
    },
  });
  exported.useOpenFinanceRefresh();
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(calls.some(row => row[0] === 'freshness'));
  assert.ok(calls.some(row => row[0] === 'timer' && row[1] === 60000));
  if (native) {
    assert.equal(calls[0][0], 'define');
    assert.ok(calls.some(row => row[0] === 'register' && row[2] === 360), 'Intervals are minutes');
    assert.ok(calls.some(row => row[0] === 'secure-key'));
    assert.equal(await task(), 1);
    assert.equal(calls.at(-1)[0], 'notifications');
  } else assert.ok(!calls.some(row => row[0] === 'register'));
  const before = calls.length;
  state.currentState = 'background'; lifecycle();
  assert.equal(calls.length, before, 'No foreground requests while inactive');
  state.currentState = 'active'; lifecycle();
  assert.equal(calls.at(-1)[0], 'freshness');
  cleanup();
  assert.ok(calls.some(row => row[0] === 'remove-listener'));
  assert.ok(calls.some(row => row[0] === 'clear-timer'));
}
Promise.resolve().then(() => check(false)).then(() => check(true)).then(() => {
  console.log('Refresh checks passed: native task definition, 360-minute schedule, Expo Go fallback and lifecycle cleanup.');
}).catch(error => { console.error(error); process.exitCode = 1; });
