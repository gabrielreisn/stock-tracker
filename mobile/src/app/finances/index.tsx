import { Link } from 'expo-router';
import { ScrollView, StyleSheet, Text, View, Pressable } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useTheme } from '@/hooks/use-theme';
import { t, type StringKey } from '@/lib/i18n';

const otherSections: StringKey[] = [];

export default function FinancesScreen() {
  const theme = useTheme();
  // Link asChild requires its child to receive one style object, not an array.
  const rowStyle = { ...styles.row, backgroundColor: theme.surface };
  const rows = otherSections.map((section) => (
    <View key={section} style={rowStyle}>
      <Text style={[styles.label, { color: theme.text }]}>{t(section)}</Text>
      <Text style={{ color: theme.textSecondary }}>{t('Coming soon')}</Text>
    </View>
  ));
  return (
    <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Finances')}</Text>
        <Link href="/finances/expenses" asChild>
          <Pressable accessibilityRole="link" style={rowStyle}>
            <Text style={[styles.label, { color: theme.text }]}>{t('Expenses')}</Text>
            <Text style={{ color: theme.textSecondary }}>›</Text>
          </Pressable>
        </Link>
        <Link href="/finances/bills" asChild>
          <Pressable accessibilityRole="link" style={rowStyle}>
            <View style={styles.copy}>
              <Text style={[styles.label, { color: theme.text }]}>{t('Bills')}</Text>
              <Text style={{ color: theme.textSecondary }}>{t('Due dates and recurring payments')}</Text>
            </View>
            <Text style={{ color: theme.textSecondary }}>›</Text>
          </Pressable>
        </Link>
        <Link href="/finances/insights" asChild>
          <Pressable accessibilityRole="link" style={rowStyle}>
            <View style={styles.copy}>
              <Text style={[styles.label, { color: theme.text }]}>{t('Insights')}</Text>
              <Text style={{ color: theme.textSecondary }}>{t('Yearly spending and category trends')}</Text>
            </View>
            <Text style={{ color: theme.textSecondary }}>›</Text>
          </Pressable>
        </Link>
        <Link href="/finances/categories" asChild>
          <Pressable accessibilityRole="link" style={rowStyle}>
            <Text style={[styles.label, { color: theme.text }]}>{t('Categories & limits')}</Text>
            <Text style={{ color: theme.textSecondary }}>›</Text>
          </Pressable>
        </Link>
        <Link href="/finances/open-finance" asChild>
          <Pressable accessibilityRole="link" style={rowStyle}>
            <Text style={[styles.label, { color: theme.text }]}>{t('Open Finance')}</Text>
            <Text style={{ color: theme.textSecondary }}>›</Text>
          </Pressable>
        </Link>
        {rows}
      </ScrollView>
    </SafeAreaView>
  );
}
const styles = StyleSheet.create({
  root: { flex: 1 }, content: { padding: 16, gap: 12 }, title: { fontSize: 34, fontWeight: '700', marginBottom: 12 },
  row: { padding: 16, minHeight: 60, borderRadius: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  label: { fontSize: 17, fontWeight: '600' }, copy: { flex: 1, gap: 4 },
});
