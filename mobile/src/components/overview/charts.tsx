import { useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Line, Polyline, Text as SvgText } from 'react-native-svg';

import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';
import { percent, type ReturnPoint } from '@/lib/overview';

export interface ChartLine { id: string; label: string; color: string; points: ReturnPoint[]; dashed?: boolean }

export function ReturnChart({ lines }: { lines: ChartLine[] }) {
  const theme = useTheme();
  const width = useRef(340);
  const [selection, setSelection] = useState<number | null>(null);
  const points = lines.flatMap(line => line.points);
  if (!points.length) return <Text style={{ color: theme.textSecondary }}>{t('Return history unavailable')}</Text>;
  const start = Math.min(...points.map(point => point.day));
  const end = Math.max(...points.map(point => point.day));
  const days = [...new Set(points.map(point => point.day))].sort();
  const selected = selection === null ? undefined : days[Math.min(days.length - 1, Math.round(selection * (days.length - 1)))];
  const low = Math.min(0, ...points.map(point => point.value));
  const high = Math.max(.01, ...points.map(point => point.value));
  const x = (day: number) => 48 + days.indexOf(day) / Math.max(1, days.length - 1) * 280;
  const y = (value: number) => 16 + (high - value) / Math.max(.01, high - low) * 158;
  const ticks = [0, .5, 1].map(fraction => {
    const value = low + fraction * (high - low);
    return <ViewTick key={fraction} y={y(value)} label={percent(value)} />;
  });
  const paths = lines.map(line => <Polyline key={line.id} points={line.points.map(point => `${x(point.day)},${y(point.value)}`).join(' ')} stroke={line.color} strokeWidth={2} strokeDasharray={line.dashed ? '5 4' : undefined} fill="none" />);
  const legend = lines.map(line => {
    const point = selected ? line.points.filter(point => point.day <= selected).at(-1) : line.points.at(-1);
    return <Text key={line.id} style={[styles.legend, { color: line.color }]}>{line.dashed ? '┄' : '━'} {line.label} · {point ? percent(point.value) : '—'}</Text>;
  });
  const date = (day: number) => `${String(day).slice(0, 4)}-${String(day).slice(4, 6)}-${String(day).slice(6)}`;
  return <View>
    <Text style={[styles.caption, { color: theme.textSecondary }]}>{selected ? date(selected) : t('Touch the chart to inspect returns')}</Text>
    <View accessible accessibilityRole="adjustable" accessibilityLabel={t('Performance')} accessibilityValue={{ text: selected ? date(selected) : date(end) }}
      accessibilityActions={[{ name: 'increment' }, { name: 'decrement' }]}
      onAccessibilityAction={event => setSelection(current => Math.max(0, Math.min(1, (current ?? 1) + (event.nativeEvent.actionName === 'increment' ? 1 : -1) / Math.max(1, days.length - 1))))}
      onTouchStart={event => setSelection(Math.max(0, Math.min(1, ((event.nativeEvent.locationX / width.current * 340 - 48) / 280))))}
      onLayout={event => { width.current = event.nativeEvent.layout.width; }}>
      <Svg width="100%" height={210} viewBox="0 0 340 210" accessible={false}>
        {ticks}{paths}
        {selected && <Line x1={x(selected)} x2={x(selected)} y1={16} y2={174} stroke={theme.textSecondary} strokeDasharray="2 4" />}
        <SvgText x={48} y={202} fontSize={10} fill={theme.textSecondary}>{date(start)}</SvgText>
        <SvgText x={328} y={202} textAnchor="end" fontSize={10} fill={theme.textSecondary}>{date(end)}</SvgText>
      </Svg>
    </View>
    <View style={styles.legends}>{legend}</View>
    {selected && <Pressable accessibilityRole="button" onPress={() => setSelection(null)} style={styles.clear}><Text style={{ color: theme.link }}>{t('Clear selection')}</Text></Pressable>}
  </View>;
}
function ViewTick({ y, label }: { y: number; label: string }) {
  const theme = useTheme();
  return <><Line x1={48} x2={328} y1={y} y2={y} stroke={theme.selected} /><SvgText x={40} y={y + 4} textAnchor="end" fontSize={10} fill={theme.textSecondary}>{label}</SvgText></>;
}
export function AllocationDonut({ slices, total }: { slices: { label: string; value: number; color: string }[]; total: number }) {
  const theme = useTheme();
  const circumference = 2 * Math.PI * 58;
  const arcs = slices.map((slice, index) => {
    const offset = slices.slice(0, index).reduce((sum, item) => sum + item.value / total * circumference, 0);
    const length = slice.value / total * circumference;
    const arc = <Circle key={slice.label} cx={80} cy={80} r={58} fill="none" stroke={slice.color} strokeWidth={24}
      strokeDasharray={`${Math.max(0, length - 2)} ${circumference}`} strokeDashoffset={-offset} rotation={-90} origin="80,80" />;
    return arc;
  });
  return <View style={styles.donut}><Svg width={160} height={160} accessible={false}>
    <Circle cx={80} cy={80} r={58} fill="none" stroke={theme.selected} strokeWidth={24} />{arcs}
    <SvgText x={80} y={78} textAnchor="middle" fontSize={12} fill={theme.textSecondary}>{t('Allocation')}</SvgText>
    <SvgText x={80} y={98} textAnchor="middle" fontSize={18} fontWeight="600" fill={theme.text}>{total > 0 ? '100%' : '—'}</SvgText>
  </Svg></View>;
}
const styles = StyleSheet.create({ caption: { fontSize: 12, marginBottom: 12 }, legends: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 }, legend: { fontSize: 12 }, donut: { alignItems: 'center' }, clear: { paddingVertical: 12, minHeight: 44 } });
