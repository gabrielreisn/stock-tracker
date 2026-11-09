import { bondStyles as s } from '@/components/bonds/styles';
import { useState } from 'react';
import { Alert, KeyboardAvoidingView, Modal, Platform, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ActionButton } from '@/components/settings/ui';
import { Card, Choices, Label, Title } from '@/components/bonds/ui';
import { useTheme } from '@/hooks/use-theme';
import { BOND_KINDS, INDEXERS, invested, money, type BondValuation } from '@/lib/bonds';
import { indexerLabel, initialBondDraft, validateBondDraft } from '@/lib/bond-input';
import { deleteBond, saveBond } from '@/lib/bond-store';
import { t, type StringKey } from '@/lib/i18n';
import type { Bond } from '@/types';

function Field({ label, value, onChange, numeric = false, placeholder }: { label: StringKey; value: string; onChange: (text: string) => void; numeric?: boolean; placeholder?: string }) {
  const theme = useTheme();
  return <View style={styles.field}><Label>{t(label)}</Label><TextInput accessibilityLabel={t(label)} value={value} onChangeText={onChange} placeholder={placeholder} placeholderTextColor={theme.textSecondary} keyboardType={numeric ? 'decimal-pad' : 'default'} autoCorrect={false} style={[styles.input, { color: theme.text, borderColor: theme.selected, backgroundColor: theme.background }]} /></View>;
}
export function BondForm({ bond, valuation, onClose }: { bond: Bond | null; valuation: BondValuation | null; onClose: () => void }) {
  const theme = useTheme();
  const [draft, setDraft] = useState(() => initialBondDraft(bond));
  function change<K extends keyof typeof draft>(key: K, value: (typeof draft)[K]) { setDraft(current => ({ ...current, [key]: value })); }
  const { rate, quantity, price, issueDay, maturityDay, digits, valid } = validateBondDraft(draft);
  const rateLabel: StringKey = draft.indexer === 'fixed' ? 'Rate (% a year)' : draft.indexer === 'cdi' ? '% of CDI' : 'Spread (% a year)';
  function save() {
    if (!valid || !issueDay || !maturityDay) return;
    saveBond({ id: bond?.id ?? 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.floor(Math.random() * 16); return (c === 'x' ? r : (r & 3) | 8).toString(16); }), kind: draft.kind, issuer: draft.issuer.trim(), issuerCNPJ: digits || undefined, code: draft.code.trim().toUpperCase(), issueDay, maturityDay, indexer: draft.indexer, rate, quantity, unitPrice: price });
    onClose();
  }
  function remove() {
    if (!bond) return;
    Alert.alert(t('Delete this bond?'), bond.issuer, [{ text: t('Cancel'), style: 'cancel' }, { text: t('Delete'), style: 'destructive', onPress: () => { deleteBond(bond.id); onClose(); } }]);
  }
  const metrics = valuation && bond ? [
    ['Invested', invested(bond)], ['Gross value', valuation.gross], ['Income tax', valuation.incomeTax], ['IOF', valuation.iof], ['Net value', valuation.net], ['Unit value', valuation.unitValue], ['At maturity (est., gross)', valuation.atMaturity],
  ] as const : [];
  const details = metrics.map(([label, value]) => <View key={label} style={s.row}><Label secondary>{t(label)}</Label><Label>{value === undefined ? '—' : money(value)}</Label></View>);
  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={[styles.root, { backgroundColor: theme.background }]}>
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={styles.root}>
          <View style={styles.header}><Title>{t(bond ? 'Edit bond' : 'Add bond')}</Title><ActionButton title={t('Cancel')} onPress={onClose} /></View>
          <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={s.content}>
            <Label secondary>{t('Changes are saved on this device.')}</Label>
            {bond && <Card>{details}</Card>}
            <Label>{t('Type')}</Label><Choices values={BOND_KINDS} selected={draft.kind} onChange={v => change('kind', v)} label={v => v} />
            <Field label="Issuer" value={draft.issuer} onChange={v => change('issuer', v)} placeholder="Banco Pine S/A" />
            <Field label="Issuer CNPJ (optional)" value={draft.cnpj} onChange={v => change('cnpj', v)} placeholder="00.000.000/0001-00" />
            <Field label="Code" value={draft.code} onChange={v => change('code', v)} />
            <Field label="Issued (YYYY-MM-DD)" value={draft.issued} onChange={v => change('issued', v)} placeholder="2026-11-09" />
            <Field label="Matures (YYYY-MM-DD)" value={draft.matures} onChange={v => change('matures', v)} placeholder="2028-11-09" />
            <Label>{t('Indexer')}</Label><Choices values={INDEXERS} selected={draft.indexer} onChange={v => change('indexer', v)} label={indexerLabel} />
            <Field label={rateLabel} numeric value={draft.rate} onChange={v => change('rate', v)} />
            <Field label="Quantity" numeric value={draft.quantity} onChange={v => change('quantity', v)} />
            <Field label="Unit price at issue (R$)" numeric value={draft.price} onChange={v => change('price', v)} />
            <View style={s.row}><Label>{t('Invested')}</Label><Title>{Number.isFinite(quantity * price) ? money(quantity * price) : '—'}</Title></View>
            {!valid && <Text style={[s.note, { color: theme.textSecondary }]}>{t('Enter an issuer, positive rate, quantity and price, valid dates from 2000–2070 with maturity after issue, and a 14-digit CNPJ if provided.')}</Text>}
            <ActionButton title={t(bond ? 'Save' : 'Add bond')} isPrimary isDisabled={!valid} onPress={save} />
            {bond && <ActionButton title={t('Delete')} onPress={remove} />}
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}
const styles = StyleSheet.create({ root: { flex: 1 }, header: { padding: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, field: { gap: 6 }, input: { borderWidth: 1, borderRadius: 10, padding: 12, fontSize: 16, minHeight: 48 } });
