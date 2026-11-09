import { Stack } from 'expo-router';
import { t } from '@/lib/i18n';

export default function InvestmentsLayout() {
  return <Stack><Stack.Screen name="index" options={{ headerShown: false }} /><Stack.Screen name="bonds" options={{ title: t('Bonds') }} /></Stack>;
}
