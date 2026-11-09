import { StyleSheet } from 'react-native';

export const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16, paddingBottom: 32 },
  card: { padding: 16, borderRadius: 16, gap: 12 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  wrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  title: { fontSize: 20, fontWeight: '600' },
  name: { fontSize: 16, lineHeight: 22, fontWeight: '600' },
  caption: { fontSize: 13, lineHeight: 19 },
  metric: { flexGrow: 1, flexShrink: 1, minWidth: 0, flexBasis: '44%', gap: 4 },
  value: { fontSize: 18, fontWeight: '600', fontVariant: ['tabular-nums'] },
  input: {
    borderWidth: 1,
    borderRadius: 10,
    minHeight: 48,
    padding: 12,
    fontSize: 16,
  },
  chip: {
    minHeight: 44,
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderRadius: 10,
  },
  separator: { height: StyleSheet.hairlineWidth },
  bar: { height: 8, borderRadius: 4, overflow: 'hidden' },
});
