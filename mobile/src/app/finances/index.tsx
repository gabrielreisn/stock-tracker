import { Link } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useTheme } from '@/hooks/use-theme';
import { t, type StringKey } from '@/lib/i18n';

const upcoming: StringKey[] = ['Expenses', 'Bills', 'Categories & limits', 'Open Finance'];

export default function FinancesScreen() {
  const theme = useTheme();
  const placeholders = upcoming.map((section) => <View key={section} style={[styles.item, { backgroundColor: theme.surface }]}>
    <Text style={{ color: theme.text }}>{t(section)}</Text>
    <Text style={{ color: theme.textSecondary }}>{t('Coming soon')}</Text>
  </View>);
  return <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
    <ScrollView contentContainerStyle={styles.content}>
      <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Finances')}</Text>
      <Link href="/finances/insights" asChild>
        <Pressable accessibilityRole="link" style={[styles.insights, { backgroundColor: theme.surface }]}>
          <View style={styles.description}>
            <Text style={[styles.label, { color: theme.text }]}>{t('Insights')}</Text>
            <Text style={{ color: theme.textSecondary }}>{t('Yearly spending and category trends')}</Text>
            <Text style={{ color: theme.accent }}>{t('Demo account')}</Text>
          </View>
          <Text style={[styles.chevron, { color: theme.textSecondary }]}>›</Text>
        </Pressable>
      </Link>
      {placeholders}
    </ScrollView>
  </SafeAreaView>;
}
const styles = StyleSheet.create({
  root: { flex: 1 }, content: { padding: 16, gap: 12 }, title: { fontSize: 34, fontWeight: '700', marginBottom: 12 },
  insights: { padding: 18, borderRadius: 14, flexDirection: 'row', alignItems: 'center', gap: 12 },
  description: { flex: 1, gap: 8 }, label: { fontSize: 19, fontWeight: '600' }, chevron: { fontSize: 28 },
  item: { padding: 16, borderRadius: 12, flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
});
