import { loadTransactionMonth } from '@/lib/pluggy-store';
import { useEffect, useState, type ReactNode } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { accountStore } from '@/lib/account-store';
import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/i18n';
import { buildYearData, classifyExpenses, finishedAverage, spendingTrend, type Focus, type MonthPoint } from '@/lib/insights';
import { categoryName, money, monthName, wholeAmount } from './format';
import { Sparkline, SpendingChart } from './spending-chart';

export function InsightsScreen() {
  const theme = useTheme();
  const { fontScale } = useWindowDimensions();
  // Both halves share row heights, including when category labels wrap at larger text sizes.
  const tableRowStyle = { height: Math.max(48, Math.ceil(36 * fontScale + 12)), borderColor: theme.selected };
  const today = new Date();
  const currentYear = today.getFullYear();
  const currentMonth = currentYear * 100 + today.getMonth() + 1;
  const { data: account } = accountStore.useValue();
  const [year, setYear] = useState(currentYear);
  useEffect(function loadSelectedYear() {
    let active = true;
    async function load() {
      for (let month = 1; month <= 12; month += 1) {
        if (!active || year * 100 + month > currentMonth) return;
        await loadTransactionMonth(year * 100 + month);
      }
    }
    void load();
    return () => { active = false; };
  }, [year, currentMonth]);
  const [focus, setFocus] = useState<Focus>('all');
  const [selectedMonth, setSelectedMonth] = useState<number>();
  const [choosingCategory, setChoosingCategory] = useState(false);
  const expenses = classifyExpenses(account.transactions, account.expenses);
  const data = buildYearData(expenses, account.expenses, year, currentMonth);
  const focusedCategory = account.expenses.categories.find((category) => category.id === focus);
  const focusName = focus === 'all' ? t('All categories') : categoryName(focusedCategory?.name);
  const limit = focus === 'all' ? account.expenses.totalLimit : focusedCategory?.limit;
  const series = data.series(focus);
  const balance = data.totalIncome - data.totalSpent;
  const subtitleStyle = { color: theme.textSecondary };

  function changeYear(next: number) {
    setYear(next);
    setSelectedMonth(undefined);
  }
  function chooseFocus(next: Focus) {
    setFocus(next);
    setSelectedMonth(undefined);
    setChoosingCategory(false);
  }
  const choices = [{ id: 'all', name: t('All categories') }, ...data.rows.map((row) => ({ id: row.id, name: categoryName(row.category?.name) }))];
  const choiceRows = choices.map((choice) => <Pressable key={choice.id ?? 'uncategorized'} accessibilityRole="button"
    accessibilityState={{ selected: choice.id === focus }} onPress={() => chooseFocus(choice.id)}
    style={[styles.choice, { backgroundColor: choice.id === focus ? theme.selected : theme.surface }]}>
    <Text style={[styles.body, { color: theme.text }]}>{choice.name}</Text>
    <Text style={{ color: theme.accent }}>{choice.id === focus ? '✓' : ''}</Text>
  </Pressable>);
  const categories = data.rows.map((row) => {
    const points = data.series(row.id);
    const last = data.lastFinished ? data.amount(row.id, data.lastFinished) : 0;
    const selected = focus === row.id;
    const name = categoryName(row.category?.name);
    return <Pressable key={row.id ?? 'uncategorized'} accessibilityRole="button" accessibilityLabel={name}
      accessibilityState={{ selected }} onPress={() => chooseFocus(selected ? 'all' : row.id)}
      style={[styles.category, { borderColor: theme.selected, backgroundColor: selected ? theme.selected : theme.surface }]}>
      <View style={styles.row}>
        <Text style={[styles.categoryName, { color: theme.text }]}>{name}</Text>
        <Sparkline series={points} limit={row.category?.limit} />
      </View>
      <View style={styles.stats}>
        <Metric label={t('Average')} value={money(finishedAverage(points))} />
        <Metric alignRight label={t('Last month')} value={money(last)} color={row.category?.limit !== undefined && last > row.category.limit ? '#dc4545' : undefined} />
      </View>
      <View style={styles.row}>
        <Trend series={points} />
        <Text style={[styles.yearTotal, { color: theme.text }]}>{t('Year')} · {money(row.total)}</Text>
      </View>
    </Pressable>;
  });
  const categoryLabels = data.rows.map((row) => <View key={row.id ?? 'uncategorized'} style={[styles.tableRow, tableRowStyle]}>
    <Text numberOfLines={2} style={[styles.nameCell, { color: theme.text }]}>{categoryName(row.category?.name)}</Text>
  </View>);
  const gridHeader = data.yearMonths.map((month) => <Text key={month} style={[styles.cell, subtitleStyle]}>{monthName(month)}</Text>);
  const gridRows = data.rows.map((row) => {
    const cells = data.yearMonths.map((month) => {
      const amount = data.amount(row.id, month);
      const color = row.category?.limit !== undefined && amount > row.category.limit ? '#dc4545' : amount === 0 ? theme.textSecondary : theme.text;
      return <Text key={month} style={[styles.cell, { color }]}>{wholeAmount(amount)}</Text>;
    });
    return <View key={row.id ?? 'uncategorized'} style={[styles.tableRow, tableRowStyle]}>
      {cells}<Text style={[styles.totalCell, { color: theme.text }]}>{wholeAmount(row.total)}</Text>
    </View>;
  });
  const totalCells = data.yearMonths.map((month) => {
    const amount = data.monthTotal(month);
    const color = account.expenses.totalLimit !== undefined && amount > account.expenses.totalLimit ? '#dc4545' : theme.text;
    return <Text key={month} style={[styles.cell, styles.bold, { color }]}>{wholeAmount(amount)}</Text>;
  });
  const empty = <Text style={[styles.empty, subtitleStyle]}>{t('No spending this year.')}</Text>;

  return <>
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <Text style={[styles.demo, { color: theme.accent }]}>{t('Personal account')}</Text>
        <View style={styles.yearPicker}>
          <YearButton label={t('Previous year')} symbol="‹" disabled={year <= currentYear - 2} onPress={() => changeYear(year - 1)} />
          <Text style={[styles.year, { color: theme.text }]}>{year}</Text>
          <YearButton label={t('Next year')} symbol="›" disabled={year >= currentYear} onPress={() => changeYear(year + 1)} />
        </View>
      </View>
      <Text style={[styles.caption, subtitleStyle]}>{t('Your connected accounts')}</Text>
      <View style={styles.tiles}>
        <Summary title={t('Spent in the year')} value={money(data.totalSpent)} detail={t('over {count} months', { count: data.months.length })} />
        <Summary title={t('Average per month')} value={money(data.averageSpent)} detail={account.expenses.totalLimit === undefined ? undefined : t('limit {amount}', { amount: money(account.expenses.totalLimit) })} />
        <Summary title={t('Income')} value={money(data.totalIncome)} />
        <Summary title={t('Balance')} value={money(balance)} color={balance >= 0 ? theme.success : '#dc4545'} />
        <Summary title={t('Highest month')} value={data.highestMonth ? money(data.highestMonth.amount) : '—'} detail={data.highestMonth ? monthName(data.highestMonth.month, true) : undefined} wide />
      </View>
      <Card title={t('Spending by month')}>
        <Pressable accessibilityRole="button" accessibilityLabel={t('Choose a category')} onPress={() => setChoosingCategory(true)}
          style={[styles.focus, { backgroundColor: theme.selected }]}>
          <Text style={[styles.body, { color: theme.text }]}>{focusName}</Text><Text style={subtitleStyle}>⌄</Text>
        </Pressable>
        {series.length ? <><SpendingChart series={series} limit={limit} selectedMonth={selectedMonth} onSelect={setSelectedMonth} /><Trend series={series} /></> : empty}
      </Card>
      <View style={styles.section}>
        <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t('Categories')}</Text>
        <Text style={[styles.caption, subtitleStyle]}>{t('Tap a category to focus the chart.')}</Text>
        {categories.length ? categories : empty}
      </View>
      <Card title={t('Month by month')}>
        <View style={styles.table}>
          <View style={[styles.frozenColumn, { borderColor: theme.selected }]}>
            <View style={[styles.tableRow, tableRowStyle]}>
              <Text numberOfLines={2} style={[styles.nameCell, subtitleStyle]}>{t('Category')}</Text>
            </View>
            {categoryLabels}
            <View style={[styles.tableRow, tableRowStyle]}>
              <Text numberOfLines={2} style={[styles.nameCell, styles.bold, { color: theme.text }]}>{t('Total')}</Text>
            </View>
          </View>
          <ScrollView horizontal showsHorizontalScrollIndicator style={styles.monthColumns}>
            <View>
              <View style={[styles.tableRow, tableRowStyle]}>
                {gridHeader}<Text style={[styles.totalCell, subtitleStyle]}>{t('Total')}</Text>
              </View>
              {gridRows}
              <View style={[styles.tableRow, tableRowStyle]}>
                {totalCells}<Text style={[styles.totalCell, { color: theme.text }]}>{wholeAmount(data.totalSpent)}</Text>
              </View>
            </View>
          </ScrollView>
        </View>
      </Card>
      <Text style={[styles.footer, subtitleStyle]}>{t('Trends use completed months only. Spending excludes income, card bill payments, investments and transfers between your own accounts.')}</Text>
    </ScrollView>
    <Modal visible={choosingCategory} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setChoosingCategory(false)}>
      <View style={[styles.modal, { backgroundColor: theme.background }]}>
        <View style={styles.row}>
          <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t('Choose a category')}</Text>
          <Pressable accessibilityRole="button" onPress={() => setChoosingCategory(false)} style={styles.close}>
            <Text style={{ color: theme.link }}>{t('Close')}</Text>
          </Pressable>
        </View>
        <ScrollView contentContainerStyle={styles.section}>{choiceRows}</ScrollView>
      </View>
    </Modal>
  </>;
}

function YearButton({ label, symbol, disabled, onPress }: { label: string; symbol: string; disabled: boolean; onPress: () => void }) {
  const theme = useTheme();
  return <Pressable accessibilityRole="button" accessibilityLabel={label} accessibilityState={{ disabled }} disabled={disabled}
    onPress={onPress} style={[styles.yearButton, disabled && styles.disabled]}>
    <Text style={[styles.chevron, { color: theme.text }]}>{symbol}</Text>
  </Pressable>;
}
function Summary({ title, value, detail, color, wide }: { title: string; value: string; detail?: string; color?: string; wide?: boolean }) {
  const theme = useTheme();
  return <View style={[styles.tile, wide && styles.wide, { backgroundColor: theme.surface }]}>
    <Text style={[styles.caption, { color: theme.textSecondary }]}>{title}</Text>
    <Text adjustsFontSizeToFit minimumFontScale={0.7} numberOfLines={1} style={[styles.value, { color: color ?? theme.text }]}>{value}</Text>
    {detail && <Text style={[styles.caption, { color: theme.textSecondary }]}>{detail}</Text>}
  </View>;
}
function Card({ title, children }: { title: string; children: ReactNode }) {
  const theme = useTheme();
  return <View style={[styles.card, { backgroundColor: theme.surface }]}>
    <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{title}</Text>{children}
  </View>;
}
function Metric({ label, value, color, alignRight = false }: { label: string; value: string; color?: string; alignRight?: boolean }) {
  const theme = useTheme();
  return <View style={styles.metric}><Text style={[styles.caption, alignRight && styles.textRight, { color: theme.textSecondary }]}>{label}</Text>
    <Text style={[styles.body, alignRight && styles.textRight, { color: color ?? theme.text }]}>{value}</Text></View>;
}
function Trend({ series }: { series: MonthPoint[] }) {
  const theme = useTheme();
  const trend = spendingTrend(series);
  const average = finishedAverage(series);
  const steady = trend && Math.abs(trend.slope) < Math.max(average * 0.02, 1);
  const color = !trend || steady ? theme.textSecondary : trend.slope > 0 ? '#dc4545' : theme.success;
  const text = !trend ? '—' : steady ? `→ ${t('steady')}` : `${trend.slope > 0 ? '↗ +' : '↘ −'}${t('{amount} a month', { amount: money(Math.abs(trend.slope)) })}`;
  return <Text style={[styles.trend, { color }]}>{text}</Text>;
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 16, paddingBottom: 32 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' },
  demo: { fontSize: 13, fontWeight: '600' },
  yearPicker: { flexDirection: 'row', alignItems: 'center' },
  year: { fontSize: 20, fontWeight: '600', fontVariant: ['tabular-nums'] },
  yearButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  chevron: { fontSize: 30 }, disabled: { opacity: 0.25 },
  tiles: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  tile: { flexBasis: '46%', flexGrow: 1, padding: 14, borderRadius: 14, gap: 8 },
  wide: { flexBasis: '100%' },
  value: { fontSize: 23, fontWeight: '600', fontVariant: ['tabular-nums'] },
  caption: { fontSize: 12, lineHeight: 18 },
  card: { padding: 16, borderRadius: 16, gap: 14 },
  heading: { fontSize: 19, fontWeight: '600' },
  body: { fontSize: 14, fontVariant: ['tabular-nums'], flexShrink: 1 },
  focus: { padding: 12, minHeight: 44, borderRadius: 10, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  section: { gap: 10 },
  category: { padding: 14, gap: 14, borderWidth: 1, borderRadius: 14 },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 12 },
  categoryName: { flex: 1, fontSize: 15, fontWeight: '600' },
  textRight: { textAlign: 'right' },
  stats: { flexDirection: 'row', gap: 24 }, metric: { flex: 1, gap: 4 },
  trend: { fontSize: 12, fontVariant: ['tabular-nums'], flexShrink: 1 },
  yearTotal: { fontSize: 12, fontWeight: '500', fontVariant: ['tabular-nums'], flexShrink: 1 },
  table: { flexDirection: 'row', alignItems: 'flex-start' },
  frozenColumn: { width: 160, flexShrink: 0, borderRightWidth: StyleSheet.hairlineWidth },
  monthColumns: { flex: 1, minWidth: 0 },
  tableRow: { flexDirection: 'row', alignItems: 'center', minHeight: 48, borderBottomWidth: StyleSheet.hairlineWidth },
  nameCell: { flex: 1, paddingRight: 12, fontSize: 12, lineHeight: 18 },
  cell: { width: 76, textAlign: 'right', paddingHorizontal: 6, fontSize: 12, fontVariant: ['tabular-nums'] },
  totalCell: { width: 96, textAlign: 'right', fontSize: 12, fontWeight: '600', fontVariant: ['tabular-nums'] },
  bold: { fontWeight: '600' },
  footer: { fontSize: 12, lineHeight: 19 }, empty: { paddingVertical: 24, textAlign: 'center', fontSize: 14 },
  modal: { flex: 1, padding: 20, paddingTop: 32, gap: 20 },
  choice: { padding: 16, minHeight: 52, borderRadius: 10, flexDirection: 'row', justifyContent: 'space-between', gap: 12 },
  close: { minHeight: 44, justifyContent: 'center', paddingHorizontal: 8 },
});
