import { Link } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '@/hooks/use-theme';
import { t, type StringKey } from '@/lib/i18n';

const pending: StringKey[] = ['Expenses', 'Bills', 'Insights', 'Open Finance'];

export default function FinancesScreen() {
  const theme = useTheme();
  const placeholders = pending.map((title) => (
    <View key={title} style={[styles.row, { backgroundColor: theme.surface }]}>
      <Text style={[styles.label, { color: theme.text }]}>{t(title)}</Text>
      <Text style={{ color: theme.textSecondary }}>{t('Coming soon')}</Text>
    </View>
  ));
  return (
    <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Finances')}</Text>
        <Link href="/finances/categories" accessibilityRole="link" style={[styles.row, { backgroundColor: theme.surface }]}>
          <Text style={[styles.label, { color: theme.link }]}>{t('Categories & limits')}  ›</Text>
        </Link>
        {placeholders}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 12 },
  title: { fontSize: 34, fontWeight: '700', marginBottom: 12 },
  row: { padding: 16, borderRadius: 12, gap: 8 },
  label: { fontSize: 17, fontWeight: '500' },
});
