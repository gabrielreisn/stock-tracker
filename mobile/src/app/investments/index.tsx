import { Link } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';

export default function InvestmentsScreen() {
  const theme = useTheme();
  const upcoming = (
    ['Stocks', 'Bonds', 'FGC Watcher', 'Fund Comparison'] as const
  ).map((title) => (
    <View key={title} style={[styles.row, { backgroundColor: theme.surface }]}>
      <Text style={{ color: theme.text }}>{t(title)}</Text>
      <Text style={{ color: theme.textSecondary }}>{t('Coming soon')}</Text>
    </View>
  ));
  return (
    <SafeAreaView
      edges={['top']}
      style={[styles.root, { backgroundColor: theme.background }]}
    >
      <ScrollView contentContainerStyle={styles.content}>
        <Text
          accessibilityRole="header"
          style={[styles.title, { color: theme.text }]}
        >
          {t('Investments')}
        </Text>
        <Link
          href="/investments/funds"
          style={[
            styles.funds,
            { backgroundColor: theme.surface, color: theme.link },
          ]}
        >
          {t('Funds')} →
        </Link>
        {upcoming}
      </ScrollView>
    </SafeAreaView>
  );
}
const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 12 },
  title: { fontSize: 34, fontWeight: '700', marginBottom: 16 },
  row: {
    padding: 20,
    borderRadius: 12,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  funds: {
    padding: 20,
    borderRadius: 12,
    fontSize: 18,
    fontWeight: '600',
    overflow: 'hidden',
  },
});
