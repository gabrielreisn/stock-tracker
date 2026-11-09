import { requireOptionalNativeModule } from 'expo';
import { Platform } from 'react-native';
import { accountStore, expenseStore } from '@/lib/account-store';
import { pendingExpenseAlerts, type ExpenseAlert } from '@/lib/expense-alerts';
import { classifyExpenses } from '@/lib/expenses';
import { createStore } from '@/lib/external-store';
import { language, t, type StringKey } from '@/lib/i18n';

const available = Platform.OS !== 'web' && !!requireOptionalNativeModule('ExpoNotificationPermissionsModule')
  && !!requireOptionalNativeModule('ExpoNotificationScheduler');
// Older installed binaries can still open this screen and explain that a rebuild is needed.
// eslint-disable-next-line @typescript-eslint/no-require-imports -- Only load when the native module is available.
const notifications: typeof import('expo-notifications') | null = available ? require('expo-notifications') : null;
const CHANNEL = 'spending-alerts';
const currency = new Intl.NumberFormat(language === 'pt' ? 'pt-BR' : 'en-US', { style: 'currency', currency: 'BRL' });
type Permission = 'unknown' | 'undetermined' | 'granted' | 'denied' | 'unavailable';
export const expenseNotificationStore = createStore({ permission: (available ? 'unknown' : 'unavailable') as Permission, error: false });

notifications?.setNotificationHandler({ handleNotification: async () => ({
  shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false,
}) });

function allowed(permission: import('expo-notifications').NotificationPermissionsStatus) {
  if (!notifications) return false;
  const status = permission.ios?.status;
  return permission.granted || status === notifications.IosAuthorizationStatus.PROVISIONAL
    || status === notifications.IosAuthorizationStatus.EPHEMERAL;
}
async function prepareChannel() {
  if (notifications && Platform.OS === 'android') {
    await notifications.setNotificationChannelAsync(CHANNEL, {
      name: t('Spending alerts'), importance: notifications.AndroidImportance.HIGH, sound: 'default',
    });
  }
}
export async function refreshExpenseNotificationPermission() {
  if (!notifications) return;
  try {
    const result = await notifications.getPermissionsAsync();
    expenseNotificationStore.set({ permission: allowed(result) ? 'granted' : result.canAskAgain ? 'undetermined' : 'denied', error: false });
  } catch { expenseNotificationStore.set({ error: true }); }
}
export async function requestExpenseNotificationPermission() {
  if (!notifications) return;
  try {
    await prepareChannel();
    const result = await notifications.requestPermissionsAsync({ ios: { allowAlert: true, allowSound: true, allowBadge: false } });
    expenseNotificationStore.set({ permission: allowed(result) ? 'granted' : result.canAskAgain ? 'undetermined' : 'denied', error: false });
    await notifyCurrentExpenses();
  } catch { expenseNotificationStore.set({ error: true }); }
}
function message(alert: ExpenseAlert) {
  if (alert.kind === 'purchase') return {
    title: t('Large purchase: {amount}', { amount: currency.format(alert.amount) }), body: alert.store,
  };
  // Built-in English category names are translation keys; custom names remain untouched.
  const name = t(alert.name as StringKey);
  return {
    title: alert.kind === 'over' ? t('{name}: limit exceeded', { name }) : t('{name}: {percent}% of the limit', { name, percent: alert.percent }),
    body: t('{spent} of {limit} spent this month.', { spent: currency.format(alert.spent), limit: currency.format(alert.limit) }),
  };
}
let delivery = Promise.resolve();
/** Serialized so foreground edits and background refreshes cannot deliver the same alert twice. */
export function notifyCurrentExpenses(): Promise<void> {
  delivery = delivery.then(deliver).catch(() => { expenseNotificationStore.set({ error: true }); });
  return delivery;
}
async function deliver() {
  if (!notifications) return;
  const permission = await notifications.getPermissionsAsync();
  if (!allowed(permission)) return; // Background work never prompts for permission.
  await prepareChannel();
  const now = new Date();
  const month = now.getFullYear() * 100 + now.getMonth() + 1;
  const data = accountStore.get().data;
  const alerts = pendingExpenseAlerts(data.expenses, classifyExpenses(data.transactions, data.expenses), month);
  const results = await Promise.allSettled(alerts.map(async (alert) => {
    await notifications.scheduleNotificationAsync({
      identifier: `expense|${alert.key}`, content: { ...message(alert), sound: 'default', data: { url: '/finances/categories' } },
      trigger: Platform.OS === 'android' ? { channelId: CHANNEL } : null,
    });
    // Read settings again so edits made during a native call are never overwritten.
    const settings = expenseStore.get().settings;
    expenseStore.set({ settings: { ...settings, notified: [...new Set([...settings.notified, alert.key])] } });
  }));
  // Wait for the whole batch before the next queued check; failed keys remain retryable.
  if (results.some(result => result.status === 'rejected')) throw new Error('Notification delivery failed');
  expenseNotificationStore.set({ error: false });
}

/** Route both a cold launch and an in-app notification tap back to the limits screen. */
export function observeExpenseNotificationResponses(openCategories: () => void) {
  if (!notifications) return () => {};
  function open(response: import('expo-notifications').NotificationResponse) {
    if (response.notification.request.content.data?.url !== '/finances/categories') return;
    openCategories();
    notifications!.clearLastNotificationResponse();
  }
  const previous = notifications.getLastNotificationResponse();
  if (previous) open(previous);
  const listener = notifications.addNotificationResponseReceivedListener(open);
  return () => listener.remove();
}
