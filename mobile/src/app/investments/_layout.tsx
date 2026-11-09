import { Stack } from 'expo-router';
import { t } from '@/lib/i18n';

export default function InvestmentsLayout() {
  return (
    <Stack>
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="fgc" options={{ title: t('FGC Watcher') }} />
      <Stack.Screen name="bonds" options={{ title: t('Bonds') }} />
      <Stack.Screen name="funds/index" options={{ title: t('Funds') }} />
      <Stack.Screen name="funds/[id]" options={{ title: t('Fund holding') }} />
    </Stack>
  );
}
