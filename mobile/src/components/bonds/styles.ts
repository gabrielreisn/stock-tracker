import { StyleSheet } from 'react-native';

export const bondStyles = StyleSheet.create({
  content: { padding: 16, paddingBottom: 36, gap: 16 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  column: { flex: 1, gap: 4 },
  metrics: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  metric: { minWidth: '45%', flexGrow: 1, gap: 4 },
  value: { fontSize: 20, fontWeight: '600', fontVariant: ['tabular-nums'] },
  separator: { height: StyleSheet.hairlineWidth, marginVertical: 4 },
  note: { fontSize: 13, lineHeight: 19 },
});
