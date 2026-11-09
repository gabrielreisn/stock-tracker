import { useState } from 'react';
import { Alert, KeyboardAvoidingView, RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { Card, Choices, Label, Title } from '@/components/bonds/ui';
import { ActionButton } from '@/components/settings/ui';
import { StockPerformance } from '@/components/stocks/performance';
import { StockForm } from '@/components/stocks/stock-form';
import { useTheme } from '@/hooks/use-theme';
import { removeDemoStock, useStockTrades } from '@/lib/demo-stock-store';
import { language, t, type StringKey } from '@/lib/i18n';
import { percent } from '@/lib/stock-performance';
import { closeBefore, holdingMetrics, isB3Stock, sortStocks, stockCurrency, stockHoldings } from '@/lib/stocks';
import { refreshStockMarket, useStockMarket } from '@/lib/use-stock-market';
import type { StockHolding, StockQuote, StockSort } from '@/types/stocks';

const sorts: StockSort[] = ['ticker', 'shares', 'average', 'price', 'value', 'gain', 'today', 'ytd'];
const sortLabels: Record<StockSort, StringKey> = { ticker: 'Ticker', shares: 'Shares', average: 'Average price', price: 'Price', value: 'Value', gain: 'Gain', today: 'Today', ytd: 'YTD' };
function money(value: number | undefined, currency = 'BRL') { return value === undefined ? '—' : value.toLocaleString(language === 'pt' ? 'pt-BR' : 'en-US', { style: 'currency', currency }); }
function HoldingCard({ holding, quotes, onEdit }: { holding: StockHolding; quotes: Record<string, StockQuote>; onEdit: () => void }) {
  const h = holding, quote = quotes[h.ticker], metrics = holdingMetrics(h, quotes);
  const currency = stockCurrency(h.ticker);
  const gainMoney = metrics.price !== undefined && h.averagePrice !== undefined ? (metrics.price - h.averagePrice) * h.quantity : undefined;
  const fields = [
    [t('Shares'), h.quantity.toLocaleString()], [t('Average price'), money(h.averagePrice, currency)],
    [t('Price'), money(metrics.price, currency)], [t('Value'), money(metrics.value)],
    [t('Gain'), `${percent(metrics.gain)} · ${money(gainMoney, currency)}`], [t('Today'), percent(metrics.today)], [t('YTD'), percent(metrics.ytd)],
  ];
  const details = fields.map(([label, value]) => <View key={label} style={styles.row}><Label secondary>{label}</Label><Label>{value}</Label></View>);
  function remove() { Alert.alert(t('Remove stock?'), h.ticker, [{ text: t('Cancel'), style: 'cancel' }, { text: t('Remove'), style: 'destructive', onPress: () => removeDemoStock(h.ticker) }]); }
  return <Card><Title>{h.ticker} · {isB3Stock(h.ticker) ? 'B3' : 'US'}</Title>{quote?.history.name && <Label secondary>{quote.history.name}</Label>}{details}
    {quote?.asOf && <Label secondary>{t('Price as of')} {new Date(quote.asOf).toLocaleString()}</Label>}
    <View style={styles.actions}><ActionButton title={t('Edit stock')} onPress={onEdit} /><ActionButton title={t('Remove')} onPress={remove} /></View></Card>;
}
function StockDividends({ holdings, quotes }: { holdings: StockHolding[]; quotes: Record<string, StockQuote> }) {
  const theme = useTheme();
  const year = new Date().getFullYear();
  const missing = holdings.filter(h => !quotes[h.ticker]).map(h => h.ticker);
  const payments = holdings.flatMap(h => (quotes[h.ticker]?.history.dividends ?? []).filter(d => Math.floor(d.day / 10000) === year).map(d => {
    const fx = isB3Stock(h.ticker) ? 1 : closeBefore(quotes['BRL=X']?.history, d.day);
    return { ticker: h.ticker, ...d, total: fx === undefined ? undefined : d.amount * h.quantity * fx };
  })).sort((a, b) => b.day - a.day || a.ticker.localeCompare(b.ticker));
  const complete = missing.length === 0 && payments.every(p => p.total !== undefined);
  const total = payments.reduce((sum, p) => sum + (p.total ?? 0), 0);
  const months = Array.from({ length: 12 }, (_, index) => payments.filter(p => Math.floor(p.day / 100) % 100 === index + 1).reduce((sum, p) => sum + (p.total ?? 0), 0));
  const max = Math.max(1, ...months);
  const bars = months.map((amount, index) => <View key={index} style={styles.month} accessibilityLabel={`${index + 1}: ${money(amount)}`}><View style={[styles.bar, { backgroundColor: theme.accent, height: amount / max * 80 }]} /><Label secondary>{index + 1}</Label></View>);
  const rows = payments.map(p => <View key={`${p.ticker}-${p.day}`} style={styles.row}><Label>{p.ticker} · {String(p.day).slice(6)}/{String(p.day).slice(4, 6)}</Label><Label>{money(p.total)}</Label></View>);
  return <Card><Title>{t('Dividends')} · {year}</Title><Label>{t('Reported distributions')}: {complete && holdings.length ? money(total) : '—'}</Label>
    {payments.length > 0 ? <>{complete && <View style={styles.bars}>{bars}</View>}{rows}</> : <Label secondary>{t('No dividend events available for this year.')}</Label>}
    <Label secondary>{t('Yahoo ex-dividend dates, multiplied by current shares, before tax. These are not confirmed payment dates. Upcoming payments are unavailable.')}</Label>
    {missing.length > 0 && <Label secondary>{t('Unavailable')}: {missing.join(', ')}</Label>}
  </Card>;
}
export function StocksScreen() {
  const theme = useTheme();
  const holdings = stockHoldings(useStockTrades());
  const tickers = holdings.map(h => h.ticker).sort();
  const market = useStockMarket(tickers);
  const [editor, setEditor] = useState<StockHolding | 'new' | null>(null);
  const [sort, setSort] = useState<StockSort>('value');
  const [ascending, setAscending] = useState(false);
  const rows = sortStocks(holdings, market.quotes, sort, ascending);
  const metrics = holdings.map(h => holdingMetrics(h, market.quotes));
  const complete = holdings.length > 0 && metrics.every(m => m.value !== undefined);
  const total = complete ? metrics.reduce((sum, m) => sum + m.value!, 0) : undefined;
  const b3 = holdings.filter(h => isB3Stock(h.ticker) && h.averagePrice !== undefined);
  const cost = b3.reduce((sum, h) => sum + h.quantity * h.averagePrice!, 0);
  const b3Value = b3.every(h => market.quotes[h.ticker]?.price !== undefined) ? b3.reduce((sum, h) => sum + h.quantity * market.quotes[h.ticker].price!, 0) : undefined;
  const cards = rows.map(h => <HoldingCard key={h.ticker} holding={h} quotes={market.quotes} onEdit={() => setEditor(h)} />);
  function refresh() { void refreshStockMarket(tickers); }
  function saved() { setEditor(null); }
  const editedHolding = editor && editor !== 'new' ? editor : undefined;
  return <KeyboardAvoidingView behavior="padding" style={[styles.root, { backgroundColor: theme.background }]}><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={market.loading} onRefresh={refresh} />}>
    <Label secondary>{t('Demo account · edits reset when the app restarts.')}</Label>
    <Card><Title>{t('Stocks')} · {holdings.length}</Title><Label>{t('Total value')}: {money(total)}</Label><Label secondary>{t('Quotes may be delayed. Pull to refresh. Missing prices are excluded from totals by showing —.')}</Label>
      {market.failed.length > 0 && <><Label secondary>{t('Some market data could not be refreshed. Previous quotes, if any, remain visible.')}: {market.failed.join(', ')}</Label><ActionButton title={t('Retry')} onPress={refresh} isDisabled={market.loading} /></>}
      <ActionButton title={t('Add stock')} onPress={() => setEditor('new')} />
    </Card>
    {editor && <StockForm key={editedHolding?.ticker ?? 'new'} holding={editedHolding} onClose={() => setEditor(null)} onSaved={saved} />}
    <StockPerformance holdings={holdings} quotes={market.quotes} rates={market.rates} />
    <Title>{t('Holdings')}</Title>
    {cost > 0 && <Card><Label>B3 · {t('Cost')}: {money(cost)}</Label><Label>{t('Value')}: {money(b3Value)}</Label><Label>{t('Gain')}: {money(b3Value === undefined ? undefined : b3Value - cost)} · {percent(b3Value === undefined ? undefined : b3Value / cost - 1)}</Label></Card>}
    <Choices values={sorts} selected={sort} onChange={value => { setSort(value); setAscending(value === 'ticker'); }} label={value => t(sortLabels[value])} />
    <ActionButton title={t(ascending ? 'Ascending ↑' : 'Descending ↓')} onPress={() => setAscending(value => !value)} />
    {holdings.length ? cards : <Card><Label secondary>{t('No stocks yet. Add a ticker and quantity.')}</Label></Card>}
    <StockDividends holdings={holdings} quotes={market.quotes} />
  </ScrollView></KeyboardAvoidingView>;
}
const styles = StyleSheet.create({ root: { flex: 1 }, content: { padding: 16, paddingBottom: 40, gap: 16 }, row: { flexDirection: 'row', justifyContent: 'space-between', gap: 12 }, actions: { flexDirection: 'row', gap: 12 }, bars: { height: 110, flexDirection: 'row', gap: 4, alignItems: 'flex-end' }, month: { flex: 1, alignItems: 'center', justifyContent: 'flex-end', height: 110 }, bar: { width: '100%', borderRadius: 3 } });
