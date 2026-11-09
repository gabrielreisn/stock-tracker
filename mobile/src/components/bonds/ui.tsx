import type { ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { useTheme } from '@/hooks/use-theme';

export function Card({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return <View style={[styles.card, { backgroundColor: theme.surface }]}>{children}</View>;
}
export function Label({ children, secondary = false }: { children: ReactNode; secondary?: boolean }) {
  const theme = useTheme();
  return <Text style={[styles.label, { color: secondary ? theme.textSecondary : theme.text }]}>{children}</Text>;
}
export function Title({ children }: { children: ReactNode }) {
  const theme = useTheme();
  return <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{children}</Text>;
}
export function Choices<T extends string>({ values, selected, onChange, label }: { values: readonly T[]; selected: T; onChange: (value: T) => void; label: (value: T) => string }) {
  const theme = useTheme();
  const buttons = values.map(value => (
    <Pressable key={value} accessibilityRole="button" accessibilityState={{ selected: selected === value }} onPress={() => onChange(value)} style={[styles.choice, { backgroundColor: selected === value ? theme.accent : theme.surface }]}>
      <Text style={{ color: selected === value ? theme.onAccent : theme.text }}>{label(value)}</Text>
    </Pressable>
  ));
  return <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.choices}>{buttons}</ScrollView>;
}
const styles = StyleSheet.create({
  card: { borderRadius: 16, padding: 16, gap: 12 },
  title: { fontSize: 20, fontWeight: '600' },
  label: { fontSize: 14, lineHeight: 20, flexShrink: 1, fontVariant: ['tabular-nums'] },
  choices: { gap: 8 },
  choice: { minHeight: 44, paddingHorizontal: 14, paddingVertical: 12, borderRadius: 12, justifyContent: 'center' },
});
