import { loadTransactionMonth } from '@/lib/pluggy-store';
import { useEffect, useState } from 'react';
import { Alert, FlatList, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import defaultCategories from '@/data/default-categories.json';

import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { billKey, calendarDate, todayKey } from '@/lib/bills';
import { billsStore, updateBill } from '@/lib/bills-store';
import { accountStore, expenseStore } from '@/lib/account-store';
import { classifyExpenses, limitStatus, moveMonth, newCategory, parseAmount, removeExpense, setExpenseCategory, setExpenseOutside } from '@/lib/expenses';
import { language, t, type StringKey } from '@/lib/i18n';
import type { Expense, ExpenseSettings, ExpenseSource } from '@/types';

const locale = language === 'pt' ? 'pt-BR' : 'en-US';
const money = new Intl.NumberFormat(locale, { style: 'currency', currency: 'BRL' });
const tabs = ['Spending', 'Income', 'To review', 'Not spending'] as const;
const sorts = ['Date', 'Store', 'Description', 'Source', 'Category', 'Value'] as const;
type Tab = typeof tabs[number];
type Sort = typeof sorts[number];
const sources: Record<ExpenseSource, StringKey> = { pix: 'Pix', creditCard: 'Credit card', debitCard: 'Debit card', autoDebit: 'Automatic debit', transfer: 'Transfer', boleto: 'Boleto', account: 'Bank account', manual: 'Manual' };
const defaultCategoryNames = new Set(defaultCategories.map(category => category.name));
function categoryName(name: string) { return defaultCategoryNames.has(name) ? t(name as StringKey) : name; }
function dateLabel(day: number) { return calendarDate(day).toLocaleDateString(locale, { day: 'numeric', month: 'short', timeZone: 'UTC' }); }
function update(settings: ExpenseSettings) { expenseStore.set({ settings }); }
function amountLabel(row: Expense) { return row.foreign?.conversion.kind === 'missing' ? t('Conversion unavailable') : money.format(row.amount); }

function Summary({ title, value, warning = false }: { title: StringKey; value: string; warning?: boolean }) {
  const theme = useTheme();
  return <View style={[styles.summary, { backgroundColor: theme.surface }]}>
    <Text style={{ color: theme.textSecondary }}>{t(title)}</Text>
    <Text style={[styles.value, { color: warning ? theme.warning : theme.text }]}>{value}</Text>
  </View>;
}

function TransactionRow({ row, category, onPress, large }: { row: Expense; category?: string; onPress: () => void; large: boolean }) {
  const theme = useTheme();
  const detail = [row.billedLater ? t('Later installment') : dateLabel(row.day), t(sources[row.source]), row.installment].filter(Boolean).join(' · ');
  const label = row.kind === 'spending' ? category ?? t('No category') : t(row.kind === 'income' ? 'Income' : 'Not spending');
  return <Pressable accessibilityRole="button" accessibilityLabel={`${row.store}, ${amountLabel(row)}, ${label}`} onPress={onPress} style={[styles.transaction, { backgroundColor: theme.surface }]}>
    <View style={styles.row}><Text style={[styles.store, styles.flex, { color: theme.text }]}>{row.store}</Text><Text style={[styles.amount, { color: row.kind === 'income' ? theme.success : large ? theme.warning : theme.text }]}>{amountLabel(row)}</Text></View>
    <Text style={[styles.caption, { color: theme.textSecondary }]}>{detail}</Text>
    <Text numberOfLines={2} style={[styles.caption, { color: theme.textSecondary }]}>{row.detail}</Text>
    <Text style={{ color: theme.link }}>{label} ›</Text>
  </Pressable>;
}

export function ExpensesScreen() {
  const theme = useTheme();
  const { settings } = expenseStore.useValue();
  const { data: account } = accountStore.useValue();
  const current = Math.floor(todayKey() / 100);
  const [month, setMonth] = useState(current);
  useEffect(function loadSelectedMonth() { void loadTransactionMonth(month); }, [month]);
  const [tab, setTab] = useState<Tab>('Spending');
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState<Sort>('Date');
  const [ascending, setAscending] = useState(false);
  const [editor, setEditor] = useState<string | null>(null);
  const all = classifyExpenses(account.transactions, settings);
  const monthly = all.filter((row) => Math.floor(row.day / 100) === month);
  const spent = monthly.filter((row) => row.kind === 'spending').reduce((sum, row) => sum + row.amount, 0);
  const income = monthly.filter((row) => row.kind === 'income').reduce((sum, row) => sum + row.amount, 0);
  const review = monthly.filter((row) => row.kind === 'spending' && !row.categoryID).length;
  const missing = monthly.filter((row) => row.foreign?.conversion.kind === 'missing').length;
  const category = (row: Expense) => settings.categories.find((c) => c.id === row.categoryID);
  const query = search.trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const rows = monthly.filter((row) => {
    const matches = tab === 'To review' ? row.kind === 'spending' && !row.categoryID : row.kind === (tab === 'Spending' ? 'spending' : tab === 'Income' ? 'income' : 'outside');
    return matches && `${row.store} ${row.detail}`.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().includes(query);
  }).sort((a, b) => {
    let result: number;
    if (sort === 'Date' || sort === 'Value') result = sort === 'Date' ? a.day - b.day : a.amount - b.amount;
    else {
      const value = (row: Expense) => sort === 'Category' ? categoryName(category(row)?.name ?? '') : sort === 'Source' ? t(sources[row.source]) : sort === 'Description' ? row.detail : row.store;
      result = value(a).localeCompare(value(b), locale);
    }
    return (ascending ? result : -result) || a.id.localeCompare(b.id);
  });
  const selected = all.find((row) => row.id === editor);
  const filterButtons = tabs.map((item) => <Pressable key={item} accessibilityRole="tab" accessibilityState={{ selected: tab === item }} onPress={() => setTab(item)} style={[styles.chip, { backgroundColor: tab === item ? theme.selected : theme.surface }]}><Text style={{ color: theme.text }}>{t(item)}</Text></Pressable>);
  const sortButtons = sorts.map((item) => <Pressable key={item} accessibilityRole="button" accessibilityState={{ selected: sort === item }} onPress={() => { if (item === sort) setAscending(!ascending); else { setSort(item); setAscending(item !== 'Date' && item !== 'Value'); } }} style={[styles.chip, { backgroundColor: theme.surface }]}><Text style={{ color: sort === item ? theme.link : theme.textSecondary }}>{t(item)}{sort === item ? ascending ? ' ↑' : ' ↓' : ''}</Text></Pressable>);
  const status = limitStatus(spent, settings.totalLimit, settings.alertAt);
  const header = <View style={styles.header}>
    <Text style={{ color: theme.link }}>{t('Personal account')}</Text>
    <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Your transactions and changes are saved on this device.')}</Text>
    <View style={styles.row}>
      <ActionButton title="‹" accessibilityLabel={t('Previous month')} onPress={() => setMonth(moveMonth(month, -1))} />
      <Text accessibilityRole="header" style={[styles.month, styles.flex, { color: theme.text }]}>{calendarDate(month * 100 + 1).toLocaleDateString(locale, { month: 'long', year: 'numeric', timeZone: 'UTC' })}</Text>
      <ActionButton title="›" accessibilityLabel={t('Next month')} isDisabled={month >= current} onPress={() => setMonth(moveMonth(month, 1))} />
    </View>
    <View style={styles.summaries}><Summary title="Spent" value={money.format(spent)} warning={status === 'warning' || status === 'over'} /><Summary title="Income" value={money.format(income)} /><Summary title="Balance" value={money.format(income - spent)} warning={income < spent} /><Summary title="To review" value={String(review)} warning={review > 0} /></View>
    {settings.totalLimit !== undefined && <Text style={{ color: status === 'within' ? theme.textSecondary : theme.warning }}>{t('Monthly limit')}: {money.format(settings.totalLimit)} · {Math.round(spent / Math.max(1, settings.totalLimit) * 100)}%</Text>}
    {missing > 0 && <Text style={{ color: theme.warning }}>{t('Totals exclude transactions without a BRL conversion.')}</Text>}
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.controls}>{filterButtons}</ScrollView>
    <TextInput accessibilityLabel={t('Search store or item')} placeholder={t('Search store or item')} placeholderTextColor={theme.textSecondary} value={search} onChangeText={setSearch} style={[styles.input, { backgroundColor: theme.surface, color: theme.text }]} />
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.controls}>{sortButtons}</ScrollView>
    <View style={styles.row}><Text style={[styles.flex, { color: theme.textSecondary }]}>{t('{count} items', { count: rows.length })}</Text><ActionButton title={t('Add purchase')} onPress={() => setEditor('new')} isPrimary /></View>
  </View>;
  return <>
    <FlatList data={rows} keyExtractor={(row) => row.id} contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content} ListHeaderComponent={header}
      renderItem={({ item }) => <TransactionRow row={item} category={category(item) ? categoryName(category(item)!.name) : undefined} large={item.amount >= (settings.largePurchase ?? Infinity)} onPress={() => setEditor(item.id)} />}
      ListEmptyComponent={<Text style={[styles.empty, { color: theme.textSecondary }]}>{t(search ? 'No matching transactions' : 'Nothing here this month')}</Text>} />
    <Modal visible={editor !== null} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setEditor(null)}>
      <SafeAreaView style={[styles.flex, { backgroundColor: theme.background }]}>
        <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <View style={styles.modalHeader}><Text accessibilityRole="header" style={[styles.store, styles.flex, { color: theme.text }]}>{selected?.store ?? t('Add purchase')}</Text><ActionButton title={t('Close')} onPress={() => setEditor(null)} /></View>
          {editor === 'new' ? <ManualForm key={month} month={month} onClose={() => setEditor(null)} /> : selected && <TransactionEditor row={selected} rows={all} onClose={() => setEditor(null)} />}
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  </>;
}

function TransactionEditor({ row, rows, onClose }: { row: Expense; rows: Expense[]; onClose: () => void }) {
  const theme = useTheme();
  const { settings } = expenseStore.useValue();
  const { data: bills } = billsStore.useValue();
  const [forStore, setForStore] = useState(false);
  const key = billKey(row);
  const tracked = bills.expenses.bills?.[key]?.tracked === true;
  function choose(id?: string) { update(setExpenseCategory(expenseStore.get().settings, row, id, forStore, rows)); }
  function confirmDelete() {
    Alert.alert(t('Delete this transaction?'), t(row.isManual ? 'This purchase will be removed.' : 'This transaction stays hidden when bank data is refreshed.'), [
      { text: t('Cancel'), style: 'cancel' }, { text: t('Delete'), style: 'destructive', onPress: () => { update(removeExpense(expenseStore.get().settings, row)); onClose(); } },
    ]);
  }
  const categories = settings.categories.map((category) => <ActionButton key={category.id} title={`${row.categoryID === category.id ? '✓ ' : ''}${categoryName(category.name)}`} onPress={() => choose(category.id)} />);
  const foreign = row.foreign ? `${row.foreign.currency} ${row.foreign.amount.toLocaleString(locale)} · ${t(row.foreign.conversion.kind === 'bank' ? 'Converted by the bank' : 'Conversion unavailable')}` : null;
  return <ScrollView contentContainerStyle={styles.form}>
    <Text style={[styles.value, { color: theme.text }]}>{amountLabel(row)}</Text>
    <Text style={{ color: theme.textSecondary }}>{dateLabel(row.day)} · {t(sources[row.source])}{row.installment ? ` · ${row.installment}` : ''}</Text>
    <Text style={{ color: theme.textSecondary }}>{row.accountName}</Text><Text style={{ color: theme.text }}>{row.detail}</Text>
    {row.billedLater && <Text style={{ color: theme.textSecondary }}>{t('Later installment')}</Text>}
    {foreign && <Text style={{ color: theme.warning }}>{foreign}</Text>}
    {row.kind === 'spending' && <><Text accessibilityRole="header" style={[styles.store, { color: theme.text }]}>{t('Category')}</Text>
      <ActionButton title={`${forStore ? '✓ ' : ''}${t('Always use for this store')}`} onPress={() => setForStore(!forStore)} />
      <ActionButton title={t('Automatic category')} onPress={() => choose()} />{categories}</>}
    <ActionButton title={t(row.kind === 'outside' ? 'Count as spending or income' : 'Move to Not spending')} onPress={() => { update(setExpenseOutside(settings, row, row.kind !== 'outside')); onClose(); }} />
    {!row.isCard && <ActionButton title={t(tracked ? 'Stop tracking as a bill' : 'Track as a bill')} onPress={() => updateBill(key, { tracked: tracked ? undefined : true })} />}
    <ActionButton title={t('Delete')} onPress={confirmDelete} />
  </ScrollView>;
}

function ManualForm({ month, onClose }: { month: number; onClose: () => void }) {
  const theme = useTheme();
  const { settings } = expenseStore.useValue();
  const day = Math.floor(todayKey() / 100) === month ? todayKey() : month * 100 + 1;
  const [date, setDate] = useState(`${Math.floor(day / 10000)}-${String(Math.floor(day / 100) % 100).padStart(2, '0')}-${String(day % 100).padStart(2, '0')}`);
  const [store, setStore] = useState('');
  const [amount, setAmount] = useState('');
  const [categoryID, setCategoryID] = useState<string>();
  const value = parseAmount(amount);
  const dateKey = Number(date.replaceAll('-', ''));
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(date) && dateKey >= 19000101 && calendarDate(dateKey).toISOString().slice(0, 10) === date;
  const valid = validDate && store.trim().length > 0 && typeof value === 'number';
  function save() {
    if (!valid || typeof value !== 'number') return;
    const current = expenseStore.get().settings;
    update({ ...current, manual: [...current.manual, { id: newCategory('').id, day: dateKey, store: store.trim(), amount: value, categoryID }] });
    onClose();
  }
  const categories = settings.categories.map((category) => <ActionButton key={category.id} title={`${categoryID === category.id ? '✓ ' : ''}${categoryName(category.name)}`} onPress={() => setCategoryID(category.id)} />);
  const input = [styles.input, { backgroundColor: theme.surface, color: theme.text }];
  return <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.form}>
    <Text style={{ color: theme.textSecondary }}>{t('Date (YYYY-MM-DD)')}</Text><TextInput accessibilityLabel={t('Date (YYYY-MM-DD)')} value={date} onChangeText={setDate} style={input} />
    <Text style={{ color: theme.textSecondary }}>{t('Store')}</Text><TextInput accessibilityLabel={t('Store')} value={store} onChangeText={setStore} style={input} />
    <Text style={{ color: theme.textSecondary }}>{t('Value (BRL, e.g. 25,90)')}</Text><TextInput accessibilityLabel={t('Value (BRL, e.g. 25,90)')} value={amount} onChangeText={setAmount} keyboardType="decimal-pad" style={input} />
    <Text style={{ color: theme.textSecondary }}>{t('Category')}</Text><ActionButton title={`${!categoryID ? '✓ ' : ''}${t('No category')}`} onPress={() => setCategoryID(undefined)} />{categories}
    <ActionButton title={t('Add purchase')} isPrimary isDisabled={!valid} onPress={save} />
  </ScrollView>;
}

const styles = StyleSheet.create({
  form: { padding: 16, gap: 14, paddingBottom: 32 }, flex: { flex: 1 }, content: { padding: 16, gap: 10, paddingBottom: 32 }, header: { gap: 14, paddingBottom: 16 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 }, month: { fontSize: 18, fontWeight: '600', textAlign: 'center' },
  summaries: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 }, summary: { flexBasis: '45%', flexGrow: 1, padding: 14, borderRadius: 12, gap: 8 },
  value: { fontSize: 22, fontWeight: '600', fontVariant: ['tabular-nums'] }, controls: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 14, minHeight: 44, justifyContent: 'center', borderRadius: 10 }, input: { padding: 14, borderRadius: 10, minHeight: 48, fontSize: 16 },
  transaction: { padding: 16, gap: 8, borderRadius: 12 }, store: { fontSize: 16, fontWeight: '600' }, amount: { fontSize: 15, fontVariant: ['tabular-nums'] },
  caption: { fontSize: 13, lineHeight: 19 }, empty: { padding: 24, textAlign: 'center' }, modalHeader: { flexDirection: 'row', padding: 16, alignItems: 'center', gap: 12 },
});
