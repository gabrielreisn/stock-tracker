import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import Svg, { Line, Polyline, Rect, Text as SvgText } from 'react-native-svg';

import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';
import { spendingTrend, type MonthPoint } from '@/lib/insights';
import { money, monthName, wholeAmount } from './format';

const RED = '#dc4545';
const ORANGE = '#e69a28';
const WIDTH = 576;
const HEIGHT = 230;
const LEFT = 64;
const TOP = 18;
const PLOT = 170;
const SLOT = 42;

export function SpendingChart({ series, limit, selectedMonth, onSelect }: {
  series: MonthPoint[]; limit?: number; selectedMonth?: number; onSelect?: (month: number) => void;
}) {
  const theme = useTheme();
  const trend = spendingTrend(series);
  const maximum = Math.max(1, limit ?? 0, ...series.map((point) => point.amount), ...trend?.points.map((point) => point.amount) ?? []) * 1.12;
  const y = (amount: number) => TOP + PLOT * (1 - amount / maximum);
  const x = (month: number) => LEFT + ((month % 100) - 1) * SLOT + SLOT / 2;
  const bars = series.map((point) => <Rect key={point.month} x={x(point.month) - 12} y={y(point.amount)} width={24}
    height={PLOT * point.amount / maximum} rx={3} fill={limit !== undefined && point.amount > limit ? RED : theme.accent}
    opacity={point.finished ? 1 : 0.4} />);
  const ticks = [0, 0.5, 1].map((fraction) => {
    const value = maximum * fraction;
    return <ViewTick key={fraction} y={y(value)} value={value} color={theme.textSecondary} grid={theme.selected} />;
  });
  const year = Math.floor(series[0]?.month / 100) || new Date().getFullYear();
  const labels = Array.from({ length: 12 }, (_, index) => {
    const month = year * 100 + index + 1;
    return <SvgText key={month} x={x(month)} y={HEIGHT - 13} fill={theme.textSecondary} fontSize={11} textAnchor="middle">{monthName(month)}</SvgText>;
  });
  const targets = series.map((point) => <Pressable key={point.month} accessibilityRole="button"
    accessibilityLabel={`${monthName(point.month, true)}: ${money(point.amount)}${point.finished ? '' : `, ${t('in progress')}`}`}
    accessibilityState={{ selected: point.month === selectedMonth }} onPress={() => onSelect?.(point.month)}
    style={[styles.target, { left: x(point.month) - SLOT / 2 }]} />);
  const linePoints = trend?.points.map((point) => `${x(point.month)},${y(point.amount)}`).join(' ');
  const selected = series.find((point) => point.month === selectedMonth);
  return <>
    <Text style={[styles.selection, { color: theme.text }]}>
      {selected ? `${monthName(selected.month, true)} · ${money(selected.amount)}${selected.finished ? '' : ` · ${t('in progress')}`}` : t('Tap a month for details. Swipe to see the whole year.')}
    </Text>
    <ScrollView horizontal showsHorizontalScrollIndicator>
      <View style={styles.canvas}>
        <Svg width={WIDTH} height={HEIGHT} accessible={false}>
          {ticks}{bars}
          {limit !== undefined && <Line x1={LEFT} x2={WIDTH} y1={y(limit)} y2={y(limit)} stroke={RED} strokeDasharray="3 4" />}
          {linePoints && <Polyline points={linePoints} fill="none" stroke={ORANGE} strokeWidth={2} strokeDasharray="5 4" />}
          {selected && <Line x1={x(selected.month)} x2={x(selected.month)} y1={TOP} y2={TOP + PLOT} stroke={theme.textSecondary} strokeDasharray="2 4" />}
          {labels}
        </Svg>
        {targets}
      </View>
    </ScrollView>
    <View style={styles.legend}>
      <Text style={{ color: theme.accent }}>■ {t('Spent')}</Text>
      {trend && <Text style={{ color: ORANGE }}>┄ {t('Trend')}</Text>}
      {limit !== undefined && <Text style={{ color: RED }}>┄ {t('Limit')} · {money(limit)}</Text>}
    </View>
  </>;
}

function ViewTick({ y, value, color, grid }: { y: number; value: number; color: string; grid: string }) {
  return <>
    <Line x1={LEFT} x2={WIDTH} y1={y} y2={y} stroke={grid} />
    <SvgText x={LEFT - 8} y={y + 4} textAnchor="end" fill={color} fontSize={10}>{wholeAmount(value)}</SvgText>
  </>;
}

export function Sparkline({ series, limit }: { series: MonthPoint[]; limit?: number }) {
  const theme = useTheme();
  const trend = spendingTrend(series);
  const max = Math.max(1, ...series.map((point) => point.amount), ...trend?.points.map((point) => point.amount) ?? []);
  const x = (month: number) => (month % 100 - 1) * 8 + 4;
  const y = (amount: number) => 30 - amount / max * 28;
  const bars = series.map((point) => <Rect key={point.month} x={x(point.month) - 2.5} y={y(point.amount)}
    width={5} height={amountHeight(point.amount, max)} rx={1} fill={limit !== undefined && point.amount > limit ? RED : theme.accent} opacity={point.finished ? 0.85 : 0.35} />);
  const line = trend?.points.map((point) => `${x(point.month)},${y(point.amount)}`).join(' ');
  return <Svg width={96} height={32} accessible={false}>{bars}
    {line && <Polyline points={line} fill="none" stroke={ORANGE} strokeWidth={1.5} strokeDasharray="3 2" />}
  </Svg>;
}
function amountHeight(amount: number, maximum: number) { return amount / maximum * 28; }

const styles = StyleSheet.create({
  canvas: { width: WIDTH, height: HEIGHT },
  target: { position: 'absolute', top: 0, width: SLOT, height: HEIGHT },
  selection: { fontSize: 12, minHeight: 34 },
  legend: { flexDirection: 'row', flexWrap: 'wrap', gap: 14, marginTop: 12 },
});
