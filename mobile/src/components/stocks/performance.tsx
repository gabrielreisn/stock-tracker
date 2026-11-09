import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import Svg, { Line, Polyline } from 'react-native-svg';
import { Card, Label, Title, Choices } from '@/components/bonds/ui';
import { useTheme } from '@/hooks/use-theme';
import { useEnabledBenchmarks } from '@/lib/benchmarks';
import type { BondRates } from '@/lib/bonds';
import { t } from '@/lib/i18n';
import { portfolioIndex, rangeStart } from '@/lib/stocks';
import type { StockHolding, StockQuote, StockRange } from '@/types/stocks';

import { percent, performanceSeries } from '@/lib/stock-performance';
const ranges: StockRange[] = ['1M', '3M', '6M', 'YTD', '1Y', '5Y'];
export function StockPerformance({ holdings, quotes, rates }: { holdings: StockHolding[]; quotes: Record<string, StockQuote>; rates: BondRates | null }) {
  const theme = useTheme();
  const enabled = useEnabledBenchmarks();
  const [range, setRange] = useState<StockRange>('YTD');
  const start = rangeStart(range);
  const portfolio = portfolioIndex(holdings, quotes, start);
  const { series, missing } = performanceSeries(portfolio, quotes, rates, start, enabled, theme, t('Stocks'));
  const values = series.flatMap(s => s.points.map(p => p.value));
  const min = Math.min(0, ...values), max = Math.max(0.01, ...values), span = max - min;
  const days = series.flatMap(s => s.points.map(p => p.day));
  const epoch = (day: number) => Date.UTC(Math.floor(day / 10000), Math.floor(day / 100) % 100 - 1, day % 100);
  const left = days.length ? epoch(Math.min(...days)) : 0, right = days.length ? epoch(Math.max(...days)) : 1;
  const paths = series.map(s => {
    const coordinates = s.points.map(p => `${(epoch(p.day) - left) / Math.max(1, right - left) * 300 + 5},${145 - (p.value - min) / span * 135}`).join(' ');
    return <Polyline key={s.id} points={coordinates} fill="none" stroke={s.color} strokeWidth={2} strokeDasharray={s.dashed ? '5 3' : undefined} />;
  });
  const legend = series.map(s => <View key={s.id} style={styles.legend}><View style={[styles.dot, { backgroundColor: s.color }]} /><Label>{s.label} {percent(s.points.at(-1)?.value)}</Label></View>);
  const dates = days.length ? `${new Date(left).toLocaleDateString()} — ${new Date(right).toLocaleDateString()}` : '';
  return <Card><Title>{t('Performance')}</Title><Choices values={ranges} selected={range} onChange={setRange} label={v => v} />
    {portfolio.length > 1 ? <><Label secondary>{percent(max)} / {percent(min)}</Label><Svg accessible accessibilityLabel={t('Stock performance chart')} viewBox="0 0 310 155" width="100%" height={180}><Line x1={5} x2={305} y1={145 - (0 - min) / span * 135} y2={145 - (0 - min) / span * 135} stroke={theme.textSecondary} strokeDasharray="2 4" />{paths}</Svg><Label secondary>{dates}</Label></> : <Label secondary>{t('Performance unavailable until all holdings have price histories and exchange rates.')}</Label>}
    <View style={styles.legends}>{legend}</View><Label secondary>{t('Current holdings, total returns in BRL. Benchmarks follow Settings. Monthly inflation uses published observations.')}</Label>
    {missing.length > 0 && <Label secondary>{t('Unavailable')}: {missing.join(', ')}</Label>}
  </Card>;
}
const styles = StyleSheet.create({ legends: { gap: 8 }, legend: { flexDirection: 'row', gap: 8, alignItems: 'center' }, dot: { width: 8, height: 8, borderRadius: 4 } });
