import { Link } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useTheme } from '@/hooks/use-theme';
import { t, type StringKey } from '@/lib/i18n';

const upcoming: StringKey[] = ['FGC Watcher', 'Fund Comparison'];
export default function InvestmentsScreen() {
  const theme = useTheme();
  // Link asChild requires its child to receive one style object, not an array.
  const cardStyle = { ...styles.card, backgroundColor: theme.surface };
  const placeholders = upcoming.map(section => <View key={section} style={cardStyle}><Text style={{ color: theme.text }}>{t(section)}</Text><Text style={{ color: theme.textSecondary }}>{t('Coming soon')}</Text></View>);
  return (
    <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Investments')}</Text>
        <Link href="/investments/stocks" asChild><Pressable accessibilityRole="button" style={cardStyle}><Text style={[styles.label, { color: theme.text }]}>{t('Stocks')}</Text><Text style={{ color: theme.textSecondary }}>{t('Demo account')} ·  ›</Text></Pressable></Link>
        <Link href="/investments/bonds" asChild><Pressable accessibilityRole="button" style={cardStyle}><Text style={[styles.label, { color: theme.text }]}>{t('Bonds')}</Text><Text style={{ color: theme.textSecondary }}>{t('Demo account')} ·  ›</Text></Pressable></Link>
        <Link href="/investments/funds" asChild><Pressable accessibilityRole="button" style={cardStyle}><Text style={[styles.label, { color: theme.text }]}>{t('Funds')}</Text><Text style={{ color: theme.textSecondary }}>{t('Demo account')} ·  ›</Text></Pressable></Link>
        {placeholders}
      </ScrollView>
    </SafeAreaView>
  );
}
const styles = StyleSheet.create({ root: { flex: 1 }, content: { padding: 16, gap: 12 }, title: { fontSize: 34, fontWeight: '700', marginBottom: 12 }, card: { borderRadius: 14, padding: 20, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 64 }, label: { fontSize: 18, fontWeight: '600' } });
