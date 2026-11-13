import { useEffect } from 'react';
import { router } from 'expo-router';
import { AppState } from 'react-native';
import { accountStore } from '@/lib/account-store';
import { expenseNotificationStore, notifyCurrentExpenses, observeExpenseNotificationResponses, refreshExpenseNotificationPermission } from '@/lib/expense-notifications';

/** Watch account edits and foreground syncs across every tab, not just the limits screen. */
export function useExpenseNotifications() {
  const { data } = accountStore.useValue();
  const { permission } = expenseNotificationStore.useValue();
  useEffect(function openExpenseNotifications() {
    return observeExpenseNotificationResponses(() => router.push('/finances/categories'));
  }, []);
  useEffect(function refreshPermissionOnResume() {
    function refresh() {
      if (AppState.currentState === 'active') {
        void refreshExpenseNotificationPermission().then(notifyCurrentExpenses);
      }
    }
    refresh();
    const listener = AppState.addEventListener('change', refresh);
    return () => listener.remove();
  }, []);
  useEffect(function notifyAfterAccountChanges() {
    if (permission === 'granted') void notifyCurrentExpenses();
  }, [data, permission]);
}
