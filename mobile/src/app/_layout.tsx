import { DarkTheme, DefaultTheme, ThemeProvider } from 'expo-router';
import { NativeTabs } from 'expo-router/native-tabs';
import { useColorScheme } from 'react-native';

import { Colors } from '@/constants/theme';
import { t } from '@/lib/i18n';

const lightNavigation = {
  ...DefaultTheme,
  colors: { ...DefaultTheme.colors, background: Colors.light.background },
};
const darkNavigation = {
  ...DarkTheme,
  colors: { ...DarkTheme.colors, background: Colors.dark.background },
};

export default function RootLayout() {
  const isDark = useColorScheme() === 'dark';
  const colors = isDark ? Colors.dark : Colors.light;

  return (
    <ThemeProvider value={isDark ? darkNavigation : lightNavigation}>
      <NativeTabs
        tintColor={colors.text}
        backgroundColor={colors.background}
        indicatorColor={colors.selected}>
        <NativeTabs.Trigger name="index">
          <NativeTabs.Trigger.Label>{t('Overview')}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="chart.pie" md="pie_chart" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="investments">
          <NativeTabs.Trigger.Label>{t('Investments')}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="chart.line.uptrend.xyaxis" md="show_chart" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="finances">
          <NativeTabs.Trigger.Label>{t('Finances')}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="list.bullet.rectangle" md="receipt_long" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="ai">
          <NativeTabs.Trigger.Label>{t('AI')}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="sparkles" md="auto_awesome" />
        </NativeTabs.Trigger>
        <NativeTabs.Trigger name="settings">
          <NativeTabs.Trigger.Label>{t('Settings')}</NativeTabs.Trigger.Label>
          <NativeTabs.Trigger.Icon sf="gearshape" md="settings" />
        </NativeTabs.Trigger>
      </NativeTabs>
    </ThemeProvider>
  );
}
