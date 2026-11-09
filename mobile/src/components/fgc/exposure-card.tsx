import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { Card, Label, Title } from '@/components/bonds/ui';
import { useTheme } from '@/hooks/use-theme';
import { describeRate, formatDay, money } from '@/lib/bonds';
import { FGC_INSTITUTION_LIMIT, fgcStatus, foldIssuer, formatCNPJ, type Exposure } from '@/lib/fgc';
import { t, type StringKey } from '@/lib/i18n';
import type { Bond, Conglomerate } from '@/types';

const statusLabels: Record<ReturnType<typeof fgcStatus>, StringKey> = {
  unknown: 'Valuation unavailable', within: 'Under 80%', near: '80–100%', above: 'Above the limit',
};
function ExposureBar({ gross, atMaturity, color }: { gross: number; atMaturity: number; color: string }) {
  const theme = useTheme();
  const scale = Math.max(FGC_INSTITUTION_LIMIT, gross, atMaturity) * 1.05;
  const currentWidth = `${gross / scale * 100}%` as const;
  const limitLeft = `${FGC_INSTITUTION_LIMIT / scale * 100}%` as const;
  const maturityLeft = `${atMaturity / scale * 100}%` as const;
  return <View accessible accessibilityLabel={`${t('Value today')}: ${money(gross)}. ${t('At maturity (est., gross)')}: ${money(atMaturity)}. ${t('Institution limit')}: ${money(FGC_INSTITUTION_LIMIT)}`} style={[styles.bar, { backgroundColor: theme.selected }]}>
    <View style={[styles.fill, { width: currentWidth, backgroundColor: color }]} />
    <View style={[styles.limit, { left: limitLeft, backgroundColor: theme.text }]} />
    {atMaturity > gross && <View style={[styles.dot, { left: maturityLeft, borderColor: color, backgroundColor: theme.surface }]} />}
  </View>;
}
function ExposureMetrics({ exposure, color }: { exposure: Exposure; color: string }) {
  const theme = useTheme();
  const { gross, atMaturity } = exposure;
  const status = fgcStatus(gross);
  const headroom = gross === null ? '—' : money(Math.abs(FGC_INSTITUTION_LIMIT - gross));
  const projectedBreach = gross !== null && atMaturity !== null && gross <= FGC_INSTITUTION_LIMIT && atMaturity > FGC_INSTITUTION_LIMIT;
  return <>
    <View style={styles.row}><Label secondary>{t('Gross value')}</Label><Title>{gross === null ? '—' : money(gross)}</Title></View>
    <View style={styles.row}><Label secondary>{t(status === 'above' ? 'Above the limit' : 'Headroom')}</Label><Text style={{ color }}>{headroom}</Text></View>
    <View style={styles.row}><Label secondary>{t('At maturity (est., gross)')}</Label><Label>{atMaturity === null ? '—' : money(atMaturity)}</Label></View>
    {projectedBreach && <Text style={{ color: theme.warning }}>{t('Interest is projected to take this group above R$ 250,000 before maturity.')}</Text>}
  </>;
}

function ConglomerateDetails({ conglomerate, names }: { conglomerate: Conglomerate; names: string[] }) {
  const theme = useTheme();
  const [expanded, setExpanded] = useState(false);
  const progress = useSharedValue(0);
  const listHeight = useSharedValue(0);
  const arrowStyle = useAnimatedStyle(() => ({ transform: [{ rotate: `${progress.get() * 90}deg` }] }));
  const listStyle = useAnimatedStyle(() => ({ height: listHeight.get() * progress.get(), opacity: progress.get() }));
  function toggle() {
    const next = !expanded;
    setExpanded(next);
    progress.set(withTiming(next ? 1 : 0, { duration: 220, easing: Easing.out(Easing.cubic) }));
  }
  const others = conglomerate.members.filter(member => !names.some(name => foldIssuer(name) === foldIssuer(member)));
  const toggleLabel = t(expanded ? 'Hide institutions' : 'Show institutions');
  const members = others.map(member => <Label key={member}>{member}</Label>);
  return <View style={styles.conglomerate}>
    <Label secondary>{t('Conglomerate {name}', { name: conglomerate.name })}</Label>
    {others.length > 0 && <Pressable
      accessibilityRole="button"
      accessibilityLabel={toggleLabel}
      accessibilityState={{ expanded }}
      onPress={toggle}
      style={styles.disclosure}>
      <Text style={[styles.disclosureLabel, { color: theme.textSecondary }]}>{toggleLabel}</Text>
      <Animated.View accessible={false} style={[styles.arrow, arrowStyle]}>
        <View style={[styles.chevron, { borderColor: theme.textSecondary }]} />
      </Animated.View>
    </Pressable>}
    <Animated.View style={[styles.memberClip, listStyle]} pointerEvents={expanded ? 'auto' : 'none'} accessibilityElementsHidden={!expanded} importantForAccessibility={expanded ? 'auto' : 'no-hide-descendants'}>
      <View style={styles.members} onLayout={event => listHeight.set(event.nativeEvent.layout.height)}>
        {members}
      </View>
    </Animated.View>
  </View>;
}

export function ExposureCard({ exposure, onEdit }: { exposure: Exposure; onEdit: (bond: Bond) => void }) {
  const theme = useTheme();
  const { names, cnpjs, conglomerate, bonds, gross, atMaturity } = exposure;
  const status = fgcStatus(gross);
  const color = status === 'above' ? '#dc2626' : status === 'near' ? theme.warning : status === 'unknown' ? theme.textSecondary : theme.success;
  const cnpjText = cnpjs.map(formatCNPJ).join(' · ');
  const rows = bonds.map(({ bond, value }) => <Pressable key={bond.id} accessibilityRole="button" accessibilityLabel={`${t('Edit bond')}: ${bond.kind} ${bond.code}`} onPress={() => onEdit(bond)} style={[styles.bond, { borderTopColor: theme.selected }]}>
    <Label>{bond.kind} · {bond.code}  ›</Label>
    <Label secondary>{describeRate(bond)}</Label>
    <View style={styles.row}><Label secondary>{t('Matures')}: {formatDay(bond.maturityDay)}</Label><Label>{value ? money(value.gross) : '—'}</Label></View>
  </Pressable>);
  return <Card>
    <Title>{names.join(' + ')}</Title>
    {cnpjs.length ? <Text selectable style={[styles.caption, { color: theme.textSecondary }]}>{cnpjText}</Text> : <Text style={{ color: theme.warning }}>{t('CNPJ unknown: edit the bonds to identify the issuer.')}</Text>}
    {conglomerate && <ConglomerateDetails conglomerate={conglomerate} names={names} />}
    <Text style={[styles.status, { color }]}>{t(statusLabels[status])}</Text>
    {gross !== null && atMaturity !== null && <ExposureBar gross={gross} atMaturity={atMaturity} color={color} />}
    <ExposureMetrics exposure={exposure} color={color} />
    {rows}
  </Card>;
}
const styles = StyleSheet.create({
  conglomerate: { gap: 4 },
  disclosure: { minHeight: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  disclosureLabel: { flexShrink: 1, fontSize: 14, lineHeight: 20 },
  arrow: { width: 20, height: 20, justifyContent: 'center', alignItems: 'center', opacity: .75 },
  chevron: { width: 7, height: 7, borderTopWidth: 1.5, borderRightWidth: 1.5, transform: [{ rotate: '45deg' }] },
  memberClip: { overflow: 'hidden' },
  members: { position: 'absolute', width: '100%', gap: 8, paddingVertical: 4 },
  row: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: 8 },
  caption: { fontSize: 12, lineHeight: 18 }, status: { fontSize: 14, fontWeight: '600' },
  bond: { borderTopWidth: StyleSheet.hairlineWidth, paddingTop: 12, gap: 6, minHeight: 48 },
  bar: { height: 12, borderRadius: 6, marginVertical: 8 }, fill: { height: 12, borderRadius: 6 },
  limit: { position: 'absolute', width: 2, height: 20, top: -4, marginLeft: -1 },
  dot: { position: 'absolute', width: 12, height: 12, top: 0, marginLeft: -6, borderRadius: 6, borderWidth: 2 },
});
