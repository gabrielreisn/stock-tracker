import Storage from 'expo-sqlite/kv-store';
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AllocationDonut, ReturnChart, type ChartLine } from './charts';
import { createDemoData } from '@/data/demo';
import { useTheme } from '@/hooks/use-theme';
import { useEnabledBenchmarks } from '@/lib/benchmarks';
import { useBonds } from '@/lib/bond-store';
import { today, money } from '@/lib/bonds';
import { demoFunds } from '@/lib/funds';
import { t } from '@/lib/i18n';
import { ASSET_CLASSES, ASSET_COLORS, buildOverview, emptyMarket, percent, rangeStart, rebase, RANGES, stockQuantities, type OverviewRange } from '@/lib/overview';
import { benchmarkLines, fetchOverviewMarket, type OverviewPrices } from '@/lib/overview-market';

const demo = createDemoData();
const labels = { stocks: 'Stocks', bonds: 'Bonds', funds: 'Funds' } as const;
const tickers = stockQuantities(demo.trades).map(([ticker]) => ticker);
function savedRange(): OverviewRange {
  try { const saved = Storage.getItemSync('overviewRange'); return RANGES.find(range => range === saved) ?? 'YTD'; } catch { return 'YTD'; }
}

export function OverviewScreen() {
  const theme = useTheme();
  const bonds = useBonds();
  const { holdings } = demoFunds.useValue();
  const enabled = useEnabledBenchmarks();
  const [range, setRange] = useState(savedRange);
  const [attempt, setAttempt] = useState(0);
  const [prices, setPrices] = useState<OverviewPrices | null>(null);
  const [loading, setLoading] = useState(true);
  const day = today();
  const earliest = Math.min(rangeStart('5Y', day, day), ...bonds.map(bond => bond.issueDay), ...demo.trades.map(trade => Number(trade.date.slice(0, 10).replaceAll('-', ''))));
  // Include an extra month for the return base and IPCA publication lag.
  const start = Math.floor(earliest / 10000) * 10000 + 101;
  useEffect(function loadOverviewPrices() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    let active = true;
    fetchOverviewMarket(tickers, start, controller.signal).then(result => { if (active) setPrices(result); })
      .finally(() => { clearTimeout(timeout); if (active) setLoading(false); });
    return () => { active = false; clearTimeout(timeout); controller.abort(); };
  }, [start, attempt]);
  const overview = useMemo(() => buildOverview(demo.trades, bonds, holdings, prices?.market ?? emptyMarket, day), [bonds, holdings, prices, day]);
  const from = rangeStart(range, day, overview.first);
  const curve = rebase(overview.curve, from);
  const last = curve.at(-1);
  const partial = overview.missing > 0;
  const lines: ChartLine[] = last ? [{ id: 'portfolio', label: t('Portfolio'), color: theme.text, points: curve }] : [];
  if (prices) {
    const references = benchmarkLines(prices, enabled, start, day, from).map(line => ({ ...line, color: theme.benchmarks[line.id] }));
    lines.push(...references);
  }
  function refresh() { setLoading(true); setAttempt(value => value + 1); }
  function selectRange(next: OverviewRange) {
    setRange(next);
    try { Storage.setItemSync('overviewRange', next); } catch { /* Selection still works for the session. */ }
  }
  const ranges = RANGES.map(option => <Pressable key={option} accessibilityRole="button" accessibilityState={{ selected: option === range }}
    onPress={() => selectRange(option)} style={[styles.range, { backgroundColor: option === range ? theme.selected : theme.surface }]}>
    <Text style={{ color: theme.text }}>{option === 'All' ? t('All') : option}</Text>
  </Pressable>);
  const tiles = ASSET_CLASSES.map(assetClass => <AssetTile key={assetClass} assetClass={assetClass} overview={overview} from={from} range={range} />);
  const allocation = overview.slices.map(slice => <View key={slice.label} style={styles.row}>
    <Text style={{ color: slice.color }}>●</Text><View style={styles.grow}><Label>{t(slice.label)}</Label></View>
    <Label>{money(slice.value)} · {percent(slice.value / overview.total)}</Label>
  </View>);
  const positions = overview.positions.filter(position => position.value !== undefined).slice(0, 10).map(position => <View key={position.id} style={styles.row}>
    <Text style={{ color: ASSET_COLORS[position.assetClass] }}>●</Text>
    <View style={styles.grow}><Text numberOfLines={2} style={{ color: theme.text }}>{position.name}</Text><Label>{position.detail}</Label></View>
    <View style={styles.amount}><Text style={{ color: theme.text }}>{money(position.value!)}</Text><Label>{overview.total > 0 ? percent(position.value! / overview.total) : '—'}</Label></View>
  </View>);
  const missing = overview.positions.filter(position => position.value === undefined).map(position => <View key={position.id} style={styles.row}><View style={styles.grow}><Text style={{ color: theme.text }}>{position.name}</Text><Label>{position.detail}</Label></View><Label>—</Label></View>);
  return <SafeAreaView edges={['top']} style={[styles.root, { backgroundColor: theme.background }]}>
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={loading} onRefresh={refresh} tintColor={theme.text} />}>
      <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Overview')}</Text>
      <Label>{t('Demo account')} · {t('Gross values in BRL')}</Label>
      <Card><Label>{t(partial ? 'Known portfolio value' : 'Total')}</Label><Text style={[styles.total, { color: theme.text }]}>{money(overview.total)}</Text>
        <Text style={{ color: last && last.value >= 0 ? theme.success : theme.textSecondary }}>{last ? `${percent(last.value)} · ${range}` : '—'}</Text>
        {partial && <Label>{t('{count} positions without a valuation', { count: overview.missing })}</Label>}
      </Card>
      <View style={styles.tiles}>{tiles}</View>
      <Card><Heading>{t('Performance')}</Heading><View style={styles.ranges}>{ranges}</View>
        {loading && <ActivityIndicator color={theme.textSecondary} />}
        <ReturnChart key={range} lines={lines} />
        <Label>{t('Returns cover available histories only. Missing prices are excluded, not treated as zero.')}</Label>
      </Card>
      <Card><Heading>{t('Allocation')}</Heading>{partial && <Label>{t('Shares of known value only')}</Label>}
        <AllocationDonut slices={overview.slices} total={overview.total} />{allocation}
      </Card>
      <Card><Heading>{t('Largest positions')}</Heading>{positions.length ? positions : <Label>{t('No valued positions')}</Label>}</Card>
      {partial && <Card><Heading>{t('Awaiting valuation')}</Heading><Label>{t('Fund prices require CVM history or a statement price. Stock and rate requests can be retried below.')}</Label>{missing}</Card>}
      <Pressable accessibilityRole="button" onPress={refresh} style={[styles.retry, { backgroundColor: theme.selected }]}><Text style={{ color: theme.text }}>{t('Refresh market data')}</Text></Pressable>
      <Label>{t("Today's holdings are treated as held throughout the range. Daily returns are weighted by the previous day's values. Bonds join on their issue date; statement-only funds count in value, not returns. Values are gross of tax.")}</Label>
    </ScrollView>
  </SafeAreaView>;
}
function AssetTile({ assetClass, overview, from, range }: { assetClass: typeof ASSET_CLASSES[number]; overview: ReturnType<typeof buildOverview>; from: number; range: OverviewRange }) {
  const theme = useTheme();
  const rows = overview.positions.filter(position => position.assetClass === assetClass);
  const complete = rows.every(position => position.value !== undefined);
  const hasValue = rows.some(position => position.value !== undefined) || !rows.length;
  const change = rebase(overview.curves[assetClass], from).at(-1);
  return <View style={[styles.tile, { backgroundColor: theme.surface }]}>
    <Label><Text style={{ color: ASSET_COLORS[assetClass] }}>● </Text>{t(labels[assetClass])}</Label>
    <Text adjustsFontSizeToFit numberOfLines={1} style={[styles.value, { color: theme.text }]}>{hasValue ? money(overview.values[assetClass]) : '—'}</Text>
    <Label>{complete && overview.total > 0 ? percent(overview.values[assetClass] / overview.total) : t('Partial valuation')}</Label>
    <Label>{change ? `${percent(change.value)} · ${range}` : '—'}</Label>
  </View>;
}
function Card({ children }: { children: ReactNode }) { const theme = useTheme(); return <View style={[styles.card, { backgroundColor: theme.surface }]}>{children}</View>; }
function Label({ children }: { children: ReactNode }) { const theme = useTheme(); return <Text style={[styles.label, { color: theme.textSecondary }]}>{children}</Text>; }
function Heading({ children }: { children: ReactNode }) { const theme = useTheme(); return <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{children}</Text>; }
const styles = StyleSheet.create({
  root: { flex: 1 }, content: { padding: 16, gap: 16, paddingBottom: 32 }, title: { fontSize: 34, fontWeight: '700' },
  card: { padding: 16, borderRadius: 16, gap: 12 }, total: { fontSize: 32, fontWeight: '600', fontVariant: ['tabular-nums'] },
  tiles: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 }, tile: { flexGrow: 1, flexBasis: 140, borderRadius: 12, padding: 14, gap: 6 },
  value: { fontSize: 22, fontWeight: '600', fontVariant: ['tabular-nums'] }, label: { fontSize: 12, lineHeight: 18 }, heading: { fontSize: 18, fontWeight: '600' },
  ranges: { flexDirection: 'row', flexWrap: 'wrap', gap: 4 }, range: { minWidth: 40, minHeight: 44, paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center', borderRadius: 8 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 4 }, grow: { flex: 1, minWidth: 0 }, amount: { alignItems: 'flex-end', maxWidth: '48%' }, retry: { minHeight: 48, alignItems: 'center', justifyContent: 'center', borderRadius: 12 },
});
