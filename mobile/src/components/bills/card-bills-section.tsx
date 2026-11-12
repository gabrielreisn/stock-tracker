import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme } from '@/hooks/use-theme';
import { cardBillPayment, groupCardBills } from '@/lib/card-bills';
import { language, t, type StringKey } from '@/lib/i18n';
import type { CardBillGroup, PluggyAccount, PluggyBill } from '@/types';

const locale = language === 'pt' ? 'pt-BR' : 'en-US';
const currencyFormats = new Map<string, Intl.NumberFormat>();
const statusLabels: Record<ReturnType<typeof cardBillPayment>['status'], StringKey> = {
  paid: 'Paid', partial: 'Partially paid', unreported: 'Payment not reported', empty: 'No amount due',
};

function statementDate(iso?: string | null): string {
  if (!iso) return '—';
  const date = new Date(`${iso.slice(0, 10)}T12:00:00Z`);
  if (!Number.isFinite(date.getTime())) return '—';
  return date.toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}

function statementMoney(amount: number | null | undefined, bill: PluggyBill): string {
  if (amount == null || !Number.isFinite(amount)) return '—';
  const code = bill.totalAmountCurrencyCode?.toUpperCase() ?? 'BRL';
  const currency = /^[A-Z]{3}$/.test(code) ? code : 'BRL';
  let formatter = currencyFormats.get(currency);
  if (!formatter) {
    formatter = new Intl.NumberFormat(locale, { style: 'currency', currency });
    currencyFormats.set(currency, formatter);
  }
  return formatter.format(amount);
}

function PaymentStatus({ bill }: { bill: PluggyBill }) {
  const theme = useTheme();
  const { status } = cardBillPayment(bill);
  const color = status === 'paid' || status === 'empty' ? theme.success : status === 'partial' ? theme.warning : theme.textSecondary;
  return (
    <View style={[styles.status, { borderColor: theme.selected }]}>
      <View style={[styles.dot, { backgroundColor: color }]} />
      <Text style={[styles.statusText, { color }]}>{t(statusLabels[status])}</Text>
    </View>
  );
}

function Statement({ bill, latest = false }: { bill: PluggyBill; latest?: boolean }) {
  const theme = useTheme();
  const { paid, remaining } = cardBillPayment(bill);
  const due = t('Due {date}', { date: statementDate(bill.dueDate) });
  const closing = bill.billClosingDate ? t('Closed {date}', { date: statementDate(bill.billClosingDate) }) : undefined;
  const minimum = bill.minimumPaymentAmount != null && remaining !== 0
    ? t('Minimum payment {amount}', { amount: statementMoney(bill.minimumPaymentAmount, bill) }) : undefined;
  return (
    <View style={[styles.statement, !latest && { borderTopWidth: StyleSheet.hairlineWidth, borderColor: theme.selected }]}>
      {latest && <Text style={[styles.eyebrow, { color: theme.textSecondary }]}>{t('Latest closed bill')}</Text>}
      <Text style={[styles.due, { color: theme.textSecondary }]}>{due}</Text>
      <View style={styles.amountRow}>
        <Text style={[latest ? styles.latestAmount : styles.historyAmount, { color: theme.text }]}>{statementMoney(bill.totalAmount, bill)}</Text>
        <PaymentStatus bill={bill} />
      </View>
      <View style={styles.details}>
        <View style={styles.metric}>
          <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Reported paid')}</Text>
          <Text style={[styles.metricValue, { color: theme.text }]}>{statementMoney(paid, bill)}</Text>
        </View>
        {remaining != null && remaining > 0 && <View style={styles.metric}>
          <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Remaining')}</Text>
          <Text style={[styles.metricValue, { color: theme.warning }]}>{statementMoney(remaining, bill)}</Text>
        </View>}
      </View>
      {closing && <Text style={[styles.caption, { color: theme.textSecondary }]}>{closing}</Text>}
      {minimum && <Text style={[styles.caption, { color: theme.textSecondary }]}>{minimum}</Text>}
    </View>
  );
}

function CardStatements({ group }: { group: CardBillGroup }) {
  const theme = useTheme();
  const [expanded, setExpanded] = useState(false);
  const [latest, ...history] = group.bills;
  const name = group.account?.marketingName ?? group.account?.name ?? t('Credit card');
  const historyLabel = t(expanded ? 'Hide previous bills' : 'Previous bills ({count})', { count: history.length });
  const historyRows = expanded ? history.map((bill) => <Statement key={bill.id} bill={bill} />) : null;
  return (
    <View style={[styles.card, { backgroundColor: theme.surface, borderColor: theme.selected }]}>
      <View style={[styles.cardHeader, { borderColor: theme.selected }]}>
        <View accessible={false} style={[styles.cardIcon, { borderColor: theme.link }]}>
          <View style={[styles.cardStripe, { backgroundColor: theme.link }]} />
        </View>
        <Text accessibilityRole="header" style={[styles.cardName, { color: theme.text }]}>{name}</Text>
      </View>
      <Statement bill={latest} latest />
      {history.length > 0 && <Pressable accessibilityRole="button" accessibilityLabel={`${name}: ${historyLabel}`}
        accessibilityState={{ expanded }} onPress={() => setExpanded(!expanded)}
        style={({ pressed }) => [styles.historyToggle, { borderColor: theme.selected }, pressed && { backgroundColor: theme.selected }]}>
        <Text style={[styles.historyLabel, { color: theme.link }]}>{historyLabel}</Text>
        <Text accessible={false} style={[styles.chevron, { color: theme.link }]}>{expanded ? '−' : '+'}</Text>
      </Pressable>}
      {historyRows}
    </View>
  );
}

export function CardBillsSection({ bills, accounts }: { bills: PluggyBill[]; accounts: PluggyAccount[] }) {
  const theme = useTheme();
  const groups = groupCardBills(bills, accounts);
  const cards = groups.map((group) => <CardStatements key={group.key} group={group} />);
  return (
    <View style={styles.section}>
      <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t('Credit card bills')}</Text>
      {cards.length > 0 ? cards : <Text style={[styles.empty, { backgroundColor: theme.surface, color: theme.textSecondary }]}>{t('No closed card bills are available from your banks.')}</Text>}
      {cards.length > 0 && <Text style={[styles.caption, styles.footer, { color: theme.textSecondary }]}>{t('Payment amounts are reported by your bank. Missing payments do not confirm an unpaid bill.')}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { gap: 12 }, title: { fontSize: 20, fontWeight: '600' },
  card: { borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, overflow: 'hidden' },
  cardHeader: { padding: 18, flexDirection: 'row', alignItems: 'center', gap: 12, borderBottomWidth: StyleSheet.hairlineWidth },
  cardName: { flex: 1, fontSize: 16, lineHeight: 23, fontWeight: '600' },
  cardIcon: { width: 28, height: 21, borderWidth: 1.5, borderRadius: 4, justifyContent: 'flex-start', paddingTop: 4 },
  cardStripe: { height: 3 }, statement: { padding: 18, gap: 10 },
  eyebrow: { fontSize: 12, fontWeight: '600', letterSpacing: 0.4 }, due: { fontSize: 14, lineHeight: 20 },
  amountRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', columnGap: 12, rowGap: 10 },
  latestAmount: { fontSize: 30, lineHeight: 38, fontWeight: '700', fontVariant: ['tabular-nums'], flexShrink: 1 },
  historyAmount: { fontSize: 20, lineHeight: 28, fontWeight: '600', fontVariant: ['tabular-nums'], flexShrink: 1 },
  status: { flexDirection: 'row', alignItems: 'center', gap: 6, borderWidth: StyleSheet.hairlineWidth, borderRadius: 20, paddingHorizontal: 10, paddingVertical: 5 },
  dot: { width: 6, height: 6, borderRadius: 3 }, statusText: { fontSize: 12, lineHeight: 17, fontWeight: '500', flexShrink: 1 },
  details: { flexDirection: 'row', flexWrap: 'wrap', gap: 24, marginTop: 4 }, metric: { gap: 4 },
  caption: { fontSize: 12, lineHeight: 18 }, metricValue: { fontSize: 15, fontWeight: '500', fontVariant: ['tabular-nums'] },
  historyToggle: { minHeight: 52, paddingHorizontal: 18, paddingVertical: 14, flexDirection: 'row', alignItems: 'center', gap: 12, borderTopWidth: StyleSheet.hairlineWidth },
  historyLabel: { flex: 1, fontSize: 14, lineHeight: 21, fontWeight: '600' }, chevron: { fontSize: 20 },
  empty: { padding: 18, borderRadius: 16, fontSize: 14, lineHeight: 21 }, footer: { paddingHorizontal: 4 },
});
