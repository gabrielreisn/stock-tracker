import { KeyboardAvoidingView, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { BenchmarksSection } from '@/components/settings/benchmarks-section';
import { OpenFinanceSection } from '@/components/settings/open-finance-section';
import { settingsStyles } from '@/components/settings/ui';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';

export default function SettingsScreen() {
  const theme = useTheme();

  return (
    <SafeAreaView collapsable={false} edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <KeyboardAvoidingView collapsable={false} behavior="padding" style={styles.root}>
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={styles.content}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled">
          <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
            {t('Settings')}
          </Text>
          <BenchmarksSection />
          <OpenFinanceSection />
          <View style={styles.sources}>
            <Text accessibilityRole="header" style={[settingsStyles.caption, styles.sourcesTitle, { color: theme.textSecondary }]}>
              {t('Sources')}
            </Text>
            <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>
              {t('Prices, USD/BRL, S&P 500, IBOV: Yahoo Finance\nCDI and IPCA: Banco Central (SGS)\nIFIX history: B3')}
            </Text>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  content: {
    flexGrow: 1,
    padding: Spacing.three,
    paddingBottom: Spacing.four + Spacing.two,
    gap: Spacing.four,
  },
  title: {
    fontSize: 34,
    fontWeight: '700',
  },
  sources: {
    marginTop: 'auto',
    paddingHorizontal: Spacing.one,
    gap: Spacing.one,
  },
  sourcesTitle: {
    fontWeight: '600',
  },
});
