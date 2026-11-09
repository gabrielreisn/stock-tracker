import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { BondForm } from '@/components/bonds/bond-form';
import { bondStyles as s } from '@/components/bonds/styles';
import { Card, Label, Title } from '@/components/bonds/ui';
import { ExposureCard } from '@/components/fgc/exposure-card';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { useBondRates, useBonds } from '@/lib/bond-store';
import { money, today, valueBond } from '@/lib/bonds';
import { buildFGC, FGC_OVERALL_LIMIT } from '@/lib/fgc';
import { useConglomerates } from '@/lib/fgc-store';
import { t } from '@/lib/i18n';
import type { Bond } from '@/types';

function ExposureSummary({ guaranteed, above, count, provisional }: { guaranteed: number | null; above: number | null; count: number; provisional: boolean }) {
  const theme = useTheme();
  const overall = guaranteed === null ? '—' : `${(guaranteed / FGC_OVERALL_LIMIT * 100).toFixed(1)}%`;
  return (
      <Card>
        <Label secondary>{t(provisional ? 'Provisional exposure · grouping unverified' : 'Exposure by financial conglomerate')}</Label>
        <View style={styles.row}><Label>{t('Guaranteed')}</Label><Title>{guaranteed === null ? '—' : money(guaranteed)}</Title></View>
        <Label secondary>{t('Across {count} groups', { count: count })}</Label>
        <View style={styles.row}><Label>{t('Above the limit')}</Label><Text style={{ color: above !== null && above > 0 ? '#dc2626' : theme.text }}>{above === null ? '—' : money(above)}</Text></View>
        <View style={styles.row}><Label>{t('Overall limit used')}</Label><Text style={{ color: guaranteed !== null && guaranteed > FGC_OVERALL_LIMIT * .9 ? theme.warning : theme.text }}>{overall}</Text></View>
        <Label secondary>{t('Of R$ 1 million per CPF every four years; prior claims are not tracked here.')}</Label>
        {guaranteed === null && <Label secondary>{t('Totals are unavailable until every eligible bond can be valued.')}</Label>}
      </Card>
  );
}

export default function FGCScreen() {
  const theme = useTheme();
  const bonds = useBonds();
  const day = today();
  const start = Math.min(day - 20000, ...bonds.map(bond => Math.floor(bond.issueDay / 10000) * 10000 + 101)) - 10000;
  const { rates, loading, failed, retry } = useBondRates(start);
  const conglomerates = useConglomerates();
  const [editing, setEditing] = useState<Bond | null>(null);
  const { exposures, guaranteed, above, uncovered } = buildFGC(bonds, rates, conglomerates.groups, day);
  const cards = exposures.map(exposure => <ExposureCard key={exposure.key} exposure={exposure} onEdit={setEditing} />);
  const uncoveredRows = uncovered.map(({ bond, value }) => <View key={bond.id} style={styles.row}><Label>{bond.kind} · {bond.issuer}</Label><Label>{value ? money(value.gross) : '—'}</Label></View>);
  const editedValue = editing ? valueBond(editing, rates, day) : null;
  const groupingPending = conglomerates.loading || conglomerates.failed;
  return <>
    <ScrollView contentInsetAdjustmentBehavior="automatic" style={{ backgroundColor: theme.background }} contentContainerStyle={s.content}>
      <Label>{t('Demo account')}</Label>
      <Label secondary>{t('Demo edits last for this session only.')}</Label>
      <Label secondary>{t('FGC guarantees up to R$ 250,000 per CPF per institution or financial conglomerate, with a R$ 1 million total limit every four years. CDB, LC, LCI and LCA are covered; CRI, CRA and debentures are not.')}</Label>
      {loading && <Label secondary>{t('Loading CDI and IPCA…')}</Label>}
      {failed && <Card><Label>{t('Rate history is unavailable. Fixed-rate bonds are still valued; other values are left blank.')}</Label><ActionButton title={t('Retry')} onPress={retry} /></Card>}
      {groupingPending && <Card><Label>{t(conglomerates.loading ? 'Loading Banco Central conglomerates…' : 'Conglomerate data unavailable. Grouped by CNPJ root or issuer name only; banks in the same group may share a limit.')}</Label>{conglomerates.failed && <ActionButton title={t('Retry')} onPress={conglomerates.retry} />}</Card>}
      <ExposureSummary guaranteed={guaranteed} above={above} count={exposures.length} provisional={groupingPending} />
      <Card><Title>{t('Reading the bars')}</Title><Label secondary>{t('Filled bar: value today · circle: estimated maturity value · vertical line: R$ 250,000 limit.')}</Label><Label secondary>{t('Under 80% · 80–100% · Above the limit')}</Label></Card>
      {!exposures.length && <Card><Title>{t('No active CDB, LC, LCI or LCA in Bonds.')}</Title></Card>}
      {cards}
      {uncovered.length > 0 && <Card><Title>{t('Not covered by the FGC')}</Title>{uncoveredRows}</Card>}
      <Label secondary>{t('FGC exposure uses gross principal plus accrued interest. Maturity estimates carry forward the latest CDI and trailing 12-month IPCA. Banco Central IF.data prudential conglomerates share one limit. Missing CNPJs can split a group; edit a bond to correct its issuer.')}</Label>
    </ScrollView>
    {editing && <BondForm key={editing.id} bond={editing} valuation={editedValue} onClose={() => setEditing(null)} />}
  </>;
}
const styles = StyleSheet.create({ row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 8 } });
