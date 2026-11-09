import { Stack } from 'expo-router';
import { t } from '@/lib/i18n';

export default function FinancesLayout() {
  return <Stack>
    <Stack.Screen name="index" options={{ headerShown: false }} />
    <Stack.Screen name="insights" options={{ title: t('Insights') }} />
  </Stack>;
}
