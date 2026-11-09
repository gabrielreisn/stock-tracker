import { bondStyles as s } from '@/components/bonds/styles';
import { StyleSheet, Text, View } from 'react-native';

import { indexerLabel } from '@/lib/bond-input';
import { Card, Label, Title } from '@/components/bonds/ui';
import { useTheme } from '@/hooks/use-theme';
import { INDEXERS, INDEXER_COLORS, describeRate, invested, money, type BondValuation } from '@/lib/bonds';
import { t } from '@/lib/i18n';
import type { Bond } from '@/types';

export interface ValuedBond { bond: Bond; value: BondValuation | null }
export function BondCharts({ rows }: { rows: ValuedBond[] }) {
  const theme = useTheme();
  const complete = rows.every(row => row.value !== null);
  const amount = (row: ValuedBond) => complete ? row.value!.net : invested(row.bond);
  const total = rows.reduce((sum, row) => sum + amount(row), 0);
  const groups = INDEXERS.map(indexer => ({ indexer, rows: rows.filter(row => row.bond.indexer === indexer), amount: rows.filter(row => row.bond.indexer === indexer).reduce((sum, row) => sum + amount(row), 0) })).filter(group => group.rows.length).sort((a, b) => b.amount - a.amount);
  const allocation = groups.map(group => {
    const share = total > 0 ? group.amount / total : 0;
    const holdings = group.rows.map(row => <View key={row.bond.id} style={styles.holding}><Label secondary>{row.bond.issuer} · {describeRate(row.bond)}</Label><Label secondary>{money(amount(row))} · {total > 0 ? (amount(row) / total * 100).toFixed(1) : '0'}%</Label></View>);
    return <View key={group.indexer} style={styles.group}><View style={s.row}><Label>{indexerLabel(group.indexer)}</Label><Label>{money(group.amount)} · {(share * 100).toFixed(1)}%</Label></View><View style={[styles.track, { backgroundColor: theme.selected }]}><View style={[styles.fill, { width: `${share * 100}%`, backgroundColor: INDEXER_COLORS[group.indexer] }]} /></View>{holdings}</View>;
  });
  const years = [...new Set(rows.map(row => Math.floor(row.bond.maturityDay / 10000)))].sort();
  const totals = years.map(year => rows.filter(row => Math.floor(row.bond.maturityDay / 10000) === year).reduce((sum, row) => sum + amount(row), 0));
  const max = Math.max(...totals, 1);
  const ladder = years.map((year, index) => {
    const slices = INDEXERS.map(indexer => {
      const value = rows.filter(row => Math.floor(row.bond.maturityDay / 10000) === year && row.bond.indexer === indexer).reduce((sum, row) => sum + amount(row), 0);
      if (value === 0) return null;
      return <View key={indexer} style={{ flex: value, backgroundColor: INDEXER_COLORS[indexer] }} />;
    });
    return <View key={year} style={styles.group}><View style={s.row}><Label>{year}</Label><Label>{money(totals[index])}</Label></View><View accessibilityLabel={`${year}: ${money(totals[index])}`} style={[styles.ladder, { width: `${totals[index] / max * 100}%` }]}>{slices}</View></View>;
  });
  const legend = groups.map(group => <View key={group.indexer} style={styles.legend}><View style={[styles.dot, { backgroundColor: INDEXER_COLORS[group.indexer] }]} /><Text style={{ color: theme.textSecondary }}>{indexerLabel(group.indexer)}</Text></View>);
  return <><Card><Title>{t('Allocation by indexer')}</Title><Label secondary>{t(complete ? 'Net value' : 'Invested · valuations unavailable')}</Label>{allocation}</Card><Card><Title>{t('Maturities')}</Title><Label secondary>{t(complete ? 'Net value today by maturity year' : 'Invested · valuations unavailable')}</Label><View style={styles.legends}>{legend}</View>{ladder}</Card></>;
}
const styles = StyleSheet.create({ group: { gap: 8 }, track: { height: 8, borderRadius: 4, overflow: 'hidden' }, fill: { height: 8, borderRadius: 4 }, holding: { paddingLeft: 12, gap: 2 }, ladder: { height: 24, flexDirection: 'row', borderRadius: 4, overflow: 'hidden' }, legends: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 }, legend: { flexDirection: 'row', gap: 6, alignItems: 'center' }, dot: { width: 8, height: 8, borderRadius: 4 } });
