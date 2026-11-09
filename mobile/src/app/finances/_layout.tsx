import { Stack } from 'expo-router';

import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';

export default function FinancesLayout() {
  const theme = useTheme();
  return (
    <Stack screenOptions={{ headerStyle: { backgroundColor: theme.background }, headerTintColor: theme.text, contentStyle: { backgroundColor: theme.background } }}>
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="categories" options={{ title: t('Categories & limits') }} />
      <Stack.Screen name="bills" options={{ title: t('Bills') }} />
    </Stack>
  );
}
