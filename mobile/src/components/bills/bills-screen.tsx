import { useState, type ReactNode } from 'react';
import { Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { CardBillsSection } from '@/components/bills/card-bills-section';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { billKey, calendarDate, classifyExpenses, daysBetween, recurringBills, trackablePayments, upcomingBills } from '@/lib/bills';
import { billsStore, refreshBills, updateBill } from '@/lib/bills-store';
import { language, t, type StringKey } from '@/lib/i18n';
import type { ExpenseSource, RecurringBill } from '@/types';

const locale = language === 'pt' ? 'pt-BR' : 'en-US';
const money = new Intl.NumberFormat(locale, { style: 'currency', currency: 'BRL' });
const sourceLabels: Record<ExpenseSource, StringKey> = {
  autoDebit: 'Automatic debit', boleto: 'Boleto', pix: 'Pix', transfer: 'Transfer', account: 'Bank account',
  manual: 'Manual', creditCard: 'Credit card', debitCard: 'Debit card',
};
const dueDays = Array.from({ length: 31 }, (_, i) => i + 1);

function dateLabel(day: number): string {
  return calendarDate(day).toLocaleDateString(locale, { day: 'numeric', month: 'short', timeZone: 'UTC' });
}

function relative(day: number, today: number, late: boolean): string {
  const days = daysBetween(today, day);
  if (late) return t('Not seen yet · expected {date}', { date: dateLabel(day) });
  if (days < 0) return t('{count} days ago', { count: -days });
  if (days === 0) return t('Today');
  if (days === 1) return t('Tomorrow');
  return t('In {count} days', { count: days });
}

function Section({ title, detail, children }: { title: StringKey; detail?: string; children: ReactNode }) {
  const theme = useTheme();
  return (
    <View style={styles.section}>
      <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t(title)}</Text>
      {detail && <Text style={[styles.caption, { color: theme.textSecondary }]}>{detail}</Text>}
      <View style={[styles.card, { backgroundColor: theme.surface }]}>{children}</View>
    </View>
  );
}

function Summary({ title, value, detail, late = false }: { title: StringKey; value: string; detail?: string; late?: boolean }) {
  const theme = useTheme();
  return (
    <View style={[styles.summary, { backgroundColor: theme.surface }]}>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{t(title)}</Text>
      <Text style={[styles.value, { color: late ? theme.warning : theme.text }]}>{value}</Text>
      {detail && <Text style={[styles.caption, { color: theme.textSecondary }]}>{detail}</Text>}
    </View>
  );
}

function Status({ bill }: { bill: RecurringBill }) {
  const theme = useTheme();
  let text = t('Due {date}', { date: dateLabel(bill.nextDue) });
  if (bill.status === 'late') text = t('Not seen yet');
  if (bill.status === 'paid') {
    const payment = bill.paidThisMonth[bill.paidThisMonth.length - 1];
    text = payment ? t('Paid {date}', { date: dateLabel(payment.day) }) : t('Marked paid');
  }
  const color = bill.status === 'paid' ? theme.success : bill.status === 'late' ? theme.warning : theme.textSecondary;
  return <Text style={[styles.status, { color, backgroundColor: theme.selected }]}>{text}</Text>;
}

function UpcomingRow({ bill, today, onPress }: { bill: RecurringBill; today: number; onPress: () => void }) {
  const theme = useTheme();
  const date = calendarDate(bill.nextDue);
  const late = bill.status === 'late';
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={t('Manage {name}', { name: bill.name })}
      onPress={onPress} style={[styles.upcomingRow, { borderColor: theme.selected }]}>
      <View style={[styles.dateBadge, { backgroundColor: theme.selected }]}>
        <Text style={[styles.month, { color: late ? theme.warning : theme.textSecondary }]}>{date.toLocaleDateString(locale, { month: 'short', timeZone: 'UTC' }).toUpperCase()}</Text>
        <Text style={[styles.dateDay, { color: theme.text }]}>{bill.nextDue % 100}</Text>
      </View>
      <View style={styles.copy}>
        <Text style={[styles.label, { color: theme.text }]}>{bill.name}</Text>
        <Text style={[styles.caption, { color: late ? theme.warning : theme.textSecondary }]}>{relative(bill.nextDue, today, late)}</Text>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Estimated')} · ≈ {money.format(bill.usual)}</Text>
      </View>
    </Pressable>
  );
}

function RecurringRow({ bill, onPress }: { bill: RecurringBill; onPress: () => void }) {
  const theme = useTheme();
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={t('Manage {name}', { name: bill.name })}
      onPress={onPress} style={[styles.billRow, { borderColor: theme.selected }]}>
      <View style={styles.row}>
        <Text style={[styles.label, styles.flex, { color: theme.text }]}>{bill.name}</Text>
        <Text style={[styles.amount, { color: theme.text }]}>≈ {money.format(bill.usual)}</Text>
      </View>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{t(sourceLabels[bill.source])} · {t(bill.dueDaySet ? 'Day {day}' : '≈ day {day}', { day: bill.dueDay })}</Text>
      {bill.installment && <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Installment {number} of {total}', bill.installment)}</Text>}
      {bill.trackedByHand && <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Tracked by you')}</Text>}
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Last paid {date} · {amount}', { date: dateLabel(bill.lastPayment.day), amount: money.format(bill.lastPayment.amount) })}</Text>
      <View style={styles.row}><Status bill={bill} /><Text style={{ color: theme.link }}>{t('Manage')} ›</Text></View>
    </Pressable>
  );
}

type Editor = { kind: 'bill'; key: string } | { kind: 'track' };

export function BillsScreen() {
  const theme = useTheme();
  const { data, day: today } = billsStore.useValue();
  const [editor, setEditor] = useState<Editor | null>(null);
  const [showHidden, setShowHidden] = useState(false);
  const expenses = classifyExpenses(data);
  const choices = data.expenses.bills ?? {};
  const recurring = recurringBills(expenses, choices, today);
  const upcoming = upcomingBills(recurring, today);
  const due = upcoming.filter((b) => b.status !== 'late');
  const late = upcoming.filter((b) => b.status === 'late');
  const paid = recurring.flatMap((b) => b.paidThisMonth).reduce((sum, p) => sum + p.amount, 0);
  const paidCount = recurring.filter((b) => b.status === 'paid').length;
  const hidden = Object.entries(choices).filter(([, c]) => c.tracked === false).map(([key]) => ({
    key, name: expenses.find((p) => billKey(p) === key)?.store ?? key,
  })).sort((a, b) => a.name.localeCompare(b.name));
  const candidates = trackablePayments(expenses, recurring, choices, today);
  const selected = editor?.kind === 'bill' ? recurring.find((b) => b.key === editor.key) : undefined;
  const upcomingRows = upcoming.map((bill) => <UpcomingRow key={bill.key} bill={bill} today={today} onPress={() => setEditor({ kind: 'bill', key: bill.key })} />);
  const recurringRows = recurring.map((bill) => <RecurringRow key={bill.key} bill={bill} onPress={() => setEditor({ kind: 'bill', key: bill.key })} />);
  const hiddenRows = showHidden ? hidden.map((bill) => (
    <View key={bill.key} style={styles.billRow}>
      <Text style={[styles.label, { color: theme.text }]}>{bill.name}</Text>
      <ActionButton title={t('Track again')} onPress={() => updateBill(bill.key, { tracked: undefined })} />
    </View>
  )) : null;
  const candidateRows = [...candidates.entries()].sort(([, a], [, b]) => a.store.localeCompare(b.store)).map(([key, row]) => (
    <View key={key} style={styles.billRow}>
      <Text style={[styles.label, { color: theme.text }]}>{row.store}</Text>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{dateLabel(row.day)} · {money.format(row.amount)} · {t(sourceLabels[row.source])}</Text>
      <ActionButton title={t('Track payment')} onPress={() => { updateBill(key, { tracked: true }); setEditor(null); }} />
    </View>
  ));
  const loanRows = data.loans.map(loan => <View key={loan.id} style={styles.section}>
    <Text style={{ color: theme.text }}>{loan.productName ?? loan.type ?? t('Loans & financing')}</Text>
    <Text style={{ color: theme.text }}>{loan.payments?.contractOutstandingBalance == null ? '—' : money.format(loan.payments.contractOutstandingBalance)}</Text>
    <Text style={{ color: theme.textSecondary }}>{loan.dueDate?.slice(0, 10) ?? '—'}</Text>
  </View>);
  return (
    <>
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={false} onRefresh={refreshBills} />}>
        <View style={styles.section}>
          <Text style={[styles.demo, { color: theme.link }]}>{t('Personal account')}</Text>
          <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Your transactions and changes are saved on this device.')}</Text>
        </View>
        <View style={styles.summaries}>
          <Summary title="Due in the next 30 days" value={`≈ ${money.format(due.reduce((sum, b) => sum + b.usual, 0))}`} detail={t('{count} bills', { count: due.length })} />
          <Summary title="Late" value={String(late.length)} detail={late.length ? money.format(late.reduce((sum, b) => sum + b.usual, 0)) : t('Nothing late')} late={late.length > 0} />
          <Summary title="Paid this month" value={money.format(paid)} detail={t('Recorded payments only')} />
          <Summary title="Recurring bills" value={String(recurring.length)} detail={t('{count} paid this month', { count: paidCount })} />
        </View>
        <Section title="Upcoming" detail={t('Late bills first, then the next 30 days')}>
          {upcomingRows.length ? upcomingRows : <Text style={[styles.empty, { color: theme.textSecondary }]}>{t('Nothing due in the next 30 days.')}</Text>}
        </Section>
        <Section title="Recurring bills" detail={t('Boletos, automatic debits and financing paid in at least 2 of the last 3 months')}>
          {recurringRows.length ? recurringRows : <Text style={[styles.empty, { color: theme.textSecondary }]}>{t('No recurring bills found yet.')}</Text>}
        </Section>
        <ActionButton title={t('Track another payment')} onPress={() => setEditor({ kind: 'track' })} />
        {hidden.length > 0 && <View style={styles.section}>
          <ActionButton title={t(showHidden ? 'Hide untracked bills' : 'Not tracked ({count})', { count: hidden.length })} onPress={() => setShowHidden(!showHidden)} />
          {hiddenRows}
        </View>}
        <CardBillsSection bills={data.cardBills} accounts={data.transactions.accounts} />
        <Section title="Loans & financing">{loanRows.length ? loanRows : <Text style={[styles.empty, { color: theme.textSecondary }]}>{t('No loan contracts are available from your banks.')}</Text>}</Section>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Due days are estimated from past payments. Tap a recurring bill to set its due day. Payments have a 3-day grace period before appearing late.')}</Text>
      </ScrollView>
      <Modal visible={editor !== null} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setEditor(null)}>
        <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]}>
          <View style={styles.modalHeader}>
            <Text accessibilityRole="header" style={[styles.heading, styles.flex, { color: theme.text }]}>{selected?.name ?? t('Track another payment')}</Text>
            <ActionButton title={t('Close')} onPress={() => setEditor(null)} />
          </View>
          <ScrollView contentContainerStyle={styles.content}>
            {selected ? <BillEditor bill={selected} today={today} onClose={() => setEditor(null)} /> : candidateRows}
            {!selected && candidateRows.length === 0 && <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('No other bank payments to track.')}</Text>}
          </ScrollView>
        </SafeAreaView>
      </Modal>
    </>
  );
}

function BillEditor({ bill, today, onClose }: { bill: RecurringBill; today: number; onClose: () => void }) {
  const theme = useTheme();
  const month = Math.floor(today / 100);
  const { data } = billsStore.useValue();
  const choice = data.expenses.bills?.[bill.key];
  const dayButtons = dueDays.map((day) => (
    <Pressable key={day} accessibilityRole="button" accessibilityLabel={t('Day {day}', { day })}
      accessibilityState={{ selected: bill.dueDaySet && bill.dueDay === day }}
      onPress={() => updateBill(bill.key, { dueDay: day })}
      style={[styles.dayButton, { backgroundColor: bill.dueDaySet && bill.dueDay === day ? theme.accent : theme.surface }]}>
      <Text style={{ color: bill.dueDaySet && bill.dueDay === day ? theme.onAccent : theme.text }}>{day}</Text>
    </Pressable>
  ));
  function togglePaid() {
    const months = choice?.paidByHand ?? [];
    updateBill(bill.key, { paidByHand: bill.paidByHand ? months.filter((m) => m !== month) : [...months, month] });
  }
  return (
    <>
      <Status bill={bill} />
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{bill.lastPayment.detail}</Text>
      {bill.paidThisMonth.length === 0 && <ActionButton title={t(bill.paidByHand ? 'Not paid this month' : 'Mark as paid this month')} onPress={togglePaid} />}
      <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('If you paid from an account that is not connected, mark it as paid here. This does not create a transaction.')}</Text>
      <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t('Due day')}</Text>
      <ActionButton title={t('Estimate from payments')} onPress={() => updateBill(bill.key, { dueDay: undefined })} isDisabled={!bill.dueDaySet} />
      <View style={styles.days}>{dayButtons}</View>
      <ActionButton title={t('Stop tracking')} onPress={() => { updateBill(bill.key, { tracked: false, paidByHand: undefined }); onClose(); }} />
    </>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 }, content: { padding: 16, gap: 24, paddingBottom: 32 }, section: { gap: 8 },
  heading: { fontSize: 20, fontWeight: '600' }, caption: { fontSize: 13, lineHeight: 19 },
  demo: { fontSize: 14, fontWeight: '600' }, summaries: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  summary: { flexGrow: 1, flexBasis: '45%', padding: 16, borderRadius: 12, gap: 6 },
  value: { fontSize: 22, fontWeight: '600', fontVariant: ['tabular-nums'] },
  card: { borderRadius: 12, overflow: 'hidden' }, row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  upcomingRow: { flexDirection: 'row', alignItems: 'center', padding: 16, gap: 12, borderBottomWidth: StyleSheet.hairlineWidth },
  copy: { flex: 1, gap: 4 }, dateBadge: { width: 48, minHeight: 52, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  month: { fontSize: 10, fontWeight: '600' }, dateDay: { fontSize: 22, fontWeight: '600' },
  label: { fontSize: 16, fontWeight: '500' }, amount: { fontSize: 15, fontVariant: ['tabular-nums'] },
  billRow: { padding: 16, gap: 10, borderBottomWidth: StyleSheet.hairlineWidth }, empty: { padding: 16, fontSize: 14, lineHeight: 21 },
  status: { fontSize: 12, fontWeight: '600', paddingHorizontal: 8, paddingVertical: 5, borderRadius: 8, alignSelf: 'flex-start', overflow: 'hidden' },
  modalHeader: { flexDirection: 'row', alignItems: 'center', gap: 16, padding: 16 },
  days: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 }, dayButton: { minWidth: 44, minHeight: 44, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
});
