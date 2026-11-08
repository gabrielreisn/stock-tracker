import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { t, type StringKey } from '@/lib/i18n';

type Props = {
  title: StringKey;
  /** The macOS sections this tab will hold, when it holds more than one. */
  sections?: StringKey[];
};

/** Stands in for a tab until its screens are ported from the macOS app. */
export function SectionPlaceholder({ title, sections = [] }: Props) {
  const theme = useTheme();

  return (
    <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
          {t(title)}
        </Text>
        <Text style={[styles.note, { color: theme.textSecondary }]}>{t('Coming soon')}</Text>
        {sections.map((section) => (
          <View key={section} style={[styles.row, { backgroundColor: theme.surface }]}>
            <Text style={[styles.rowLabel, { color: theme.text }]}>{t(section)}</Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  content: {
    padding: Spacing.three,
    gap: Spacing.two,
  },
  title: {
    fontSize: 34,
    fontWeight: '700',
  },
  note: {
    fontSize: 15,
    marginBottom: Spacing.three,
  },
  row: {
    padding: Spacing.three,
    borderRadius: 12,
  },
  rowLabel: {
    fontSize: 16,
  },
});
