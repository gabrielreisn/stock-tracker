const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const root = path.resolve(__dirname, '../src');
const fixedDate = new Date('2026-11-09T15:00:00Z');
class Clock extends Date { constructor(...args) { super(...(args.length ? args : [fixedDate])); } }

function runtime({ native = true, platform = 'ios' } = {}) {
  let data = { expenses: { categories: [{ id: 'food', name: 'Food', symbol: 'cart', limit: 100, pluggyKeywords: ['groceries'] }],
    rules: {}, overrides: {}, manual: [], alertAt: 0.8, notified: [] },
    transactions: { accounts: [{ id: 'bank', type: 'BANK' }], months: {} } };
  const calls = [];
  let permission = { granted: true, canAskAgain: true };
  let fail = false;
  let handler;
  const modules = new Map();
  const nativeAPI = {
    IosAuthorizationStatus: { PROVISIONAL: 3, EPHEMERAL: 4 }, AndroidImportance: { HIGH: 4 },
    setNotificationHandler: value => { handler = value; },
    getPermissionsAsync: async () => permission,
    requestPermissionsAsync: async options => { calls.push(['permission', options]); permission = { granted: true }; return permission; },
    setNotificationChannelAsync: async () => calls.push(['channel']),
    scheduleNotificationAsync: async request => { if (fail) throw new Error('Scheduling failed'); calls.push(['notification', request]); },
  };
  const accountStore = { get: () => ({ data }), set: value => { data = value.data; } };
  const expenseStore = { get: () => ({ settings: data.expenses }), set: ({ settings }) => { data = { ...data, expenses: settings }; } };
  function load(file) {
    let absolute = file.startsWith('@/') ? path.join(root, file.slice(2)) : file;
    if (!path.extname(absolute)) absolute += '.ts';
    if (modules.has(absolute)) return modules.get(absolute);
    const exports = {};
    modules.set(absolute, exports);
    const code = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    vm.runInNewContext(code, { exports, Date: Clock, Intl, require(name) {
      if (name === 'expo') return { requireOptionalNativeModule: () => native ? {} : null };
      if (name === 'expo-notifications') { assert.ok(native); return nativeAPI; }
      if (name === 'react-native') return { Platform: { OS: platform } };
      if (name === 'react') return { useSyncExternalStore: (_, snapshot) => snapshot() };
      if (name === '@/lib/account-store') return { accountStore, expenseStore };
      if (name === '@/lib/i18n') return { language: 'en', t: (key, values = {}) => key.replace(/\{(\w+)\}/g, (_, name) => values[name] ?? name) };
      return load(name.startsWith('@/') ? name : path.resolve(path.dirname(absolute), name));
    } }, { filename: absolute });
    return exports;
  }
  return { load, calls, get data() { return data; }, get handler() { return handler; },
    permission: value => { permission = value; }, failure: value => { fail = value; } };
}
function spend(app, amount, id = 'purchase') {
  app.data.transactions.months = { 202611: [{ id, accountId: 'bank', amount: -amount, type: 'DEBIT',
    date: '2026-11-09T12:00:00Z', description: 'Market', category: 'Groceries' }] };
}
async function main() {
  const app = runtime();
  const api = app.load('@/lib/expense-notifications');
  const alerts = app.load('@/lib/expense-alerts');
  const { classifyExpenses } = app.load('@/lib/expenses');
  spend(app, 79);
  await api.notifyCurrentExpenses();
  assert.equal(app.calls.length, 0);
  spend(app, 80);
  await Promise.all([api.notifyCurrentExpenses(), api.notifyCurrentExpenses()]);
  const deliveries = () => app.calls.filter(call => call[0] === 'notification');
  assert.equal(deliveries().length, 1, 'Exactly 80% warns once even with concurrent checks');
  assert.ok(app.data.expenses.notified.includes('202611|food|warn'));
  spend(app, 110);
  await api.notifyCurrentExpenses();
  assert.equal(deliveries().length, 2, 'Crossing the limit sends one additional notification');
  assert.ok(deliveries()[1][1].content.title.includes('exceeded'));
  assert.equal((await app.handler.handleNotification()).shouldShowBanner, true);
  // Persisted markers are honored by a fresh module instance (like an app restart).
  await api.notifyCurrentExpenses();
  assert.equal(deliveries().length, 2);
  app.data.expenses.largePurchase = 100;
  spend(app, 150, 'large');
  await api.notifyCurrentExpenses();
  assert.equal(deliveries().length, 3);
  assert.ok(app.data.expenses.notified.includes('big|large'));
  assert.equal(deliveries()[2][1].content.data.url, '/finances/categories');
  await api.notifyCurrentExpenses();
  assert.equal(deliveries().length, 3);
  const restarted = runtime();
  Object.assign(restarted.data, JSON.parse(JSON.stringify(app.data)));
  await restarted.load('@/lib/expense-notifications').notifyCurrentExpenses();
  assert.equal(restarted.calls.length, 0, 'Persisted markers prevent duplicates after restart');

  // Permission denial never consumes a notification key; granting it later delivers the snapshot.
  const denied = runtime();
  const deniedAPI = denied.load('@/lib/expense-notifications');
  denied.permission({ granted: false, canAskAgain: false, ios: { status: 1 } });
  spend(denied, 80);
  await deniedAPI.notifyCurrentExpenses();
  assert.equal(denied.data.expenses.notified.length, 0);
  await deniedAPI.refreshExpenseNotificationPermission();
  assert.equal(deniedAPI.expenseNotificationStore.get().permission, 'denied');
  await deniedAPI.requestExpenseNotificationPermission();
  assert.equal(denied.calls.filter(call => call[0] === 'notification').length, 1);
  assert.equal(denied.calls[0][1].ios.allowAlert, true);

  const retry = runtime();
  const retryAPI = retry.load('@/lib/expense-notifications');
  spend(retry, 80); retry.failure(true);
  await retryAPI.notifyCurrentExpenses();
  assert.equal(retry.data.expenses.notified.length, 0);
  assert.equal(retryAPI.expenseNotificationStore.get().error, true);
  retry.failure(false);
  await retryAPI.notifyCurrentExpenses();
  assert.equal(retry.data.expenses.notified.length, 1);

  const android = runtime({ platform: 'android' });
  const androidAPI = android.load('@/lib/expense-notifications');
  spend(android, 80);
  await androidAPI.requestExpenseNotificationPermission();
  assert.equal(android.calls[0][0], 'channel', 'Android channel precedes permission request');
  const missing = runtime({ native: false });
  const missingAPI = missing.load('@/lib/expense-notifications');
  await missingAPI.notifyCurrentExpenses();
  assert.equal(missingAPI.expenseNotificationStore.get().permission, 'unavailable');

  const rows = classifyExpenses(app.data.transactions, app.data.expenses);
  const nextMonth = rows.map(row => ({ ...row, day: 20261209 }));
  assert.ok(alerts.pendingExpenseAlerts(app.data.expenses, nextMonth, 202612).some(alert => alert.key === '202612|food|over'));
  const laterInstallment = rows.map(row => ({ ...row, billedLater: true }));
  const clean = { ...app.data.expenses, notified: [] };
  assert.ok(!alerts.pendingExpenseAlerts(clean, laterInstallment, 202611).some(alert => alert.kind === 'purchase'));
  assert.ok(!alerts.pendingExpenseAlerts(clean, rows, 202610).length, 'Historical spending cannot notify this month');
  const lowerThreshold = { ...clean, alertAt: 0.5 };
  assert.ok(alerts.pendingExpenseAlerts(lowerThreshold, rows.map(row => ({ ...row, amount: 50 })), 202611).length);
  const monthly = { ...clean, totalLimit: 100 };
  assert.ok(alerts.pendingExpenseAlerts(monthly, rows, 202611).some(alert => alert.key === '202611|total|over'));

  const order = app.load('@/lib/category-order');
  const categories = [{ id: 'a', limit: 10 }, { id: 'b' }, { id: 'c' }];
  assert.equal(order.reorderCategory(categories, 'a', 2).map(item => item.id).join(','), 'b,c,a');
  assert.equal(order.reorderCategory(categories, 'c', 0).map(item => item.id).join(','), 'c,a,b');
  assert.equal(order.reorderCategory(categories, 'a', -1), categories);
  assert.equal(order.reorderCategory(categories, 'missing', 0), categories);
  assert.equal(order.reorderCategory(categories, 'a', 2)[2].limit, 10);
  assert.equal(order.categoryDropIndex([{ y: 0, height: 100 }, { y: 100, height: 150 }, { y: 250, height: 80 }], 280), 2);
  // Variable-height rows must preview the exact final positions without overlaps or gaps.
  const frames = [{ id: 'a', y: 0, height: 100 }, { id: 'b', y: 100, height: 150 }, { id: 'c', y: 250, height: 80 }];
  const down = order.categoryDragOffsets(frames, 'a', 2);
  assert.equal(down.a, 230);
  assert.equal(down.b, -100);
  assert.equal(down.c, -100);
  const up = order.categoryDragOffsets(frames, 'c', 0);
  assert.equal(up.c, -250);
  assert.equal(up.a, 80);
  assert.equal(up.b, 80);
  for (const source of frames) {
    for (let destination = 0; destination < frames.length; destination += 1) {
      const offsets = order.categoryDragOffsets(frames, source.id, destination);
      const preview = frames.map(frame => ({ ...frame, y: frame.y + offsets[frame.id] })).sort((a, b) => a.y - b.y);
      assert.equal(preview[0].y, 0);
      assert.equal(preview[1].y, preview[0].height);
      assert.equal(preview[2].y, preview[0].height + preview[1].height);
      assert.equal(preview[2].y + preview[2].height, 330);
      assert.equal(preview[destination].id, source.id);
    }
  }
  console.log('Notification checks passed: thresholds, deduplication, permissions, retries, background integration and drag ordering.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
