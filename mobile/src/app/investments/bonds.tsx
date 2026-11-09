import { bondStyles as s } from '@/components/bonds/styles';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { BondCharts, type ValuedBond } from '@/components/bonds/bond-charts';
import { BondForm } from '@/components/bonds/bond-form';
import { Card, Choices, Label, Title } from '@/components/bonds/ui';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { BOND_KINDS, describeRate, formatDay, invested, isFGCCovered, isTaxExempt, money, number, today, valueBond } from '@/lib/bonds';
import { useBondRates, useBonds } from '@/lib/bond-store';
import { t, type StringKey } from '@/lib/i18n';
import type { Bond } from '@/types';

const SORTS = ['issuer', 'issued', 'matures', 'rate', 'quantity', 'gross', 'tax', 'net', 'gain'] as const;
type Sort = typeof SORTS[number];
const sortLabels: Record<Sort, StringKey> = { issuer: 'Issuer', issued: 'Issued', matures: 'Matures', rate: 'Rate', quantity: 'Quantity', gross: 'Gross value', tax: 'Income tax', net: 'Net value', gain: 'Return' };
function compare(a: ValuedBond, b: ValuedBond, sort: Sort) {
  if (sort === 'issuer') return a.bond.issuer.localeCompare(b.bond.issuer);
  if (sort === 'rate') return describeRate(a.bond).localeCompare(describeRate(b.bond));
  if (sort === 'issued') return a.bond.issueDay - b.bond.issueDay;
  if (sort === 'matures') return a.bond.maturityDay - b.bond.maturityDay;
  if (sort === 'quantity') return a.bond.quantity - b.bond.quantity;
  if (!a.value || !b.value) return a.value ? -1 : b.value ? 1 : 0;
  if (sort === 'tax') return a.value.incomeTax + a.value.iof - b.value.incomeTax - b.value.iof;
  if (sort === 'gain') return a.value.gain / invested(a.bond) - b.value.gain / invested(b.bond);
  return a.value[sort] - b.value[sort];
}
function Metric({ label, value, gain = false }: { label: StringKey; value: string; gain?: boolean }) {
  const theme = useTheme();
  return <View style={s.metric}><Label secondary>{t(label)}</Label><Text style={[s.value, { color: gain ? theme.success : theme.text }]}>{value}</Text></View>;
}
function Holding({ row, onEdit }: { row: ValuedBond; onEdit: () => void }) {
  const theme = useTheme();
  const { bond, value } = row;
  const matured = bond.maturityDay <= today();
  const metrics: [StringKey, string][] = [['Gross value', value ? money(value.gross) : '—'], ['Income tax + IOF', value ? money(value.incomeTax + value.iof) : '—'], ['Net value', value ? money(value.net) : '—'], ['Return', value ? `${value.gain >= 0 ? '+' : ''}${(value.gain / invested(bond) * 100).toFixed(2)}%` : '—']];
  const details = metrics.map(([label, text]) => <View key={label} style={s.row}><Label secondary>{t(label)}</Label><Label>{text}</Label></View>);
  return <Pressable accessibilityRole="button" accessibilityLabel={`${t('Edit bond')}: ${bond.issuer}, ${bond.code}`} onPress={onEdit} style={styles.holding}>
    <View style={s.row}><View style={s.column}><Title>{bond.issuer}</Title><Label secondary>{bond.code}</Label></View><Label>›</Label></View>
    <Label>{describeRate(bond)} · {number(bond.quantity)} × {money(bond.unitPrice)}</Label>
    <Label secondary>{t('Issued')}: {formatDay(bond.issueDay)}</Label>
    <Text style={{ color: matured ? theme.warning : theme.textSecondary }}>{t(matured ? 'Matured' : 'Matures')}: {formatDay(bond.maturityDay)}</Text>
    <Label secondary>{t(isFGCCovered(bond.kind) ? 'FGC covered' : 'Not FGC covered')}</Label>
    {details}
    {!value && <Label secondary>{t('Valuation unavailable')}</Label>}
  </Pressable>;
}
function PortfolioSummary({ rows }: { rows: ValuedBond[] }) {
  const complete = rows.every(row => row.value !== null);
  const totalInvested = rows.reduce((sum, row) => sum + invested(row.bond), 0);
  const gross = rows.reduce((sum, row) => sum + (row.value?.gross ?? 0), 0);
  const tax = rows.reduce((sum, row) => sum + (row.value ? row.value.incomeTax + row.value.iof : 0), 0);
  const gain = gross - totalInvested;
  const gainText = complete ? `${money(gain)} (${totalInvested > 0 ? (gain / totalInvested * 100).toFixed(2) : '0'}%)` : '—';
  return <Card><Title>{t('Portfolio summary')}</Title><View style={s.metrics}><Metric label="Invested" value={money(totalInvested)} /><Metric label="Gross value" value={complete ? money(gross) : '—'} /><Metric label="Income tax + IOF" value={complete ? money(tax) : '—'} /><Metric label="Net value" value={complete ? money(gross - tax) : '—'} /><Metric label="Gain" value={gainText} gain={complete && gain >= 0} /></View></Card>;
}

function HoldingGroups({ rows, sort, ascending, onEdit }: { rows: ValuedBond[]; sort: Sort; ascending: boolean; onEdit: (bond: Bond) => void }) {
  const groups = BOND_KINDS.map(kind => {
    const holdings = rows.filter(row => row.bond.kind === kind).sort((a, b) => compare(a, b, sort) * (ascending ? 1 : -1));
    if (!holdings.length) return null;
    const items = holdings.map(row => <Holding key={row.bond.id} row={row} onEdit={() => onEdit(row.bond)} />);
    const net = holdings.every(row => row.value) ? money(holdings.reduce((sum, row) => sum + row.value!.net, 0)) : '—';
    return <Card key={kind}><View style={s.row}><Title>{kind}</Title>{isTaxExempt(kind) && <Label secondary>{t('Tax exempt')}</Label>}</View>{items}<View style={s.row}><Label>{t('Total net')}</Label><Title>{net}</Title></View></Card>;
  });
  return <>{groups}</>;
}

export default function BondsScreen() {
  const theme = useTheme();
  const bonds = useBonds();
  // Include prior IPCA publications and at least twelve months for projections.
  const start = Math.min(today() - 20000, ...bonds.map(bond => Math.floor(bond.issueDay / 10000) * 10000 + 101)) - 10000;
  const { rates, loading, failed, retry } = useBondRates(start);
  const [editing, setEditing] = useState<{ bond: Bond | null } | null>(null);
  const [sort, setSort] = useState<Sort>('matures');
  const [ascending, setAscending] = useState(true);
  const rows = bonds.map(bond => ({ bond, value: valueBond(bond, rates) }));
  const editedValue = editing?.bond ? valueBond(editing.bond, rates) : null;
  return <>
    <ScrollView
      style={[styles.root, { backgroundColor: theme.background }]}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={s.content}>
    <View style={s.row}><View style={s.column}><Label>{t('Demo account')}</Label><Label secondary>{t('Demo edits last for this session only.')}</Label></View><ActionButton title={t('Add bond')} isPrimary onPress={() => setEditing({ bond: null })} /></View>
    {loading && <Label secondary>{t('Loading CDI and IPCA…')}</Label>}
    {failed && <Card><Label>{t('Rate history is unavailable. Fixed-rate bonds are still valued; other values are left blank.')}</Label><ActionButton title={t('Retry')} onPress={retry} /></Card>}
    {bonds.length === 0 ? <Card><Title>{t('No bonds yet')}</Title><Label secondary>{t('Add CDBs, LCAs and other fixed income with their rate and dates.')}</Label></Card> : <>
      <PortfolioSummary rows={rows} />
      <View style={s.row}><Title>{t('Holdings')}</Title><ActionButton title={t(ascending ? 'Ascending ↑' : 'Descending ↓')} onPress={() => setAscending(value => !value)} /></View>
      <Choices values={SORTS} selected={sort} onChange={setSort} label={key => t(sortLabels[key])} />
      <HoldingGroups rows={rows} sort={sort} ascending={ascending} onEdit={bond => setEditing({ bond })} /><BondCharts rows={rows} />
      <Text style={[s.note, { color: theme.textSecondary }]}>{t('Values use business days over 252 with ANBIMA holidays, daily CDI compounding and monthly IPCA anniversaries. Income tax ranges from 22.5% to 15% on gains; exempt types pay no income tax. IOF applies within 30 days. Maturity projections carry forward the latest CDI or trailing 12-month IPCA and are estimates.')}</Text>
    </>}
  </ScrollView>{editing && <BondForm key={editing.bond?.id ?? 'new'} bond={editing.bond} valuation={editedValue} onClose={() => setEditing(null)} />}</>;
}
const styles = StyleSheet.create({ root: { flex: 1 }, holding: { gap: 8, paddingVertical: 14 } });
