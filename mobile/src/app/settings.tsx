import { KeyboardAvoidingView, ScrollView, StyleSheet, Text } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { BenchmarksSection } from '@/components/settings/benchmarks-section';
import { OpenFinanceSection } from '@/components/settings/open-finance-section';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';

export default function SettingsScreen() {
  const theme = useTheme();

  return (
    <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <KeyboardAvoidingView behavior="padding" style={styles.root}>
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled">
          <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
            {t('Settings')}
          </Text>
          <BenchmarksSection />
          <OpenFinanceSection />
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
    padding: Spacing.three,
    gap: Spacing.four,
  },
  title: {
    fontSize: 34,
    fontWeight: '700',
  },
});
