import { Linking, StyleSheet, Text, View } from 'react-native';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { expenseNotificationStore, notifyCurrentExpenses, refreshExpenseNotificationPermission, requestExpenseNotificationPermission } from '@/lib/expense-notifications';
import { t } from '@/lib/i18n';

export function NotificationPermission() {
  const theme = useTheme();
  const { permission, error } = expenseNotificationStore.useValue();
  const explanation = permission === 'unavailable' ? t('Rebuild the app to enable device notifications.')
    : permission === 'granted' ? t('Spending notifications are enabled.')
    : permission === 'denied' ? t('Notifications are blocked. Allow them in device Settings.')
    : t('Allow notifications for category limits and large purchases.');
  async function enable() {
    if (permission === 'denied') await Linking.openSettings();
    else await requestExpenseNotificationPermission();
  }
  async function retry() {
    await refreshExpenseNotificationPermission();
    await notifyCurrentExpenses();
  }
  return (
    <View style={styles.content}>
      <Text style={[styles.label, { color: theme.text }]}>{t('Spending notifications')}</Text>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{explanation}</Text>
      {permission !== 'granted' && permission !== 'unavailable' && <ActionButton title={t(permission === 'denied' ? 'Open device Settings' : 'Enable notifications')} onPress={() => void enable()} />}
      {error && <>
        <Text accessibilityRole="alert" style={{ color: theme.warning }}>{t('Could not send notifications. Please try again.')}</Text>
        <ActionButton title={t('Retry notifications')} onPress={() => void retry()} />
      </>}
    </View>
  );
}
const styles = StyleSheet.create({
  content: { padding: 16, gap: 10 }, label: { fontSize: 16, fontWeight: '500' }, caption: { fontSize: 13, lineHeight: 19 },
});
