import { Link } from 'expo-router';
import { useState } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { accountStore } from '@/lib/account-store';
import { investmentKey, isClosedInvestment } from '@/lib/open-finance';
import { backgroundSyncAvailable } from '@/lib/pluggy-refresh';
import { institutionsOf, sync, usePluggy } from '@/lib/pluggy-store';
import { t } from '@/lib/i18n';

function money(value?: number | null, currency = 'BRL') {
  if (value == null) return '—';
  try { return value.toLocaleString(undefined, { style: 'currency', currency }); }
  catch { return `${value.toLocaleString()} ${currency}`; }
}

export default function OpenFinanceScreen() {
  const theme = useTheme();
  const state = usePluggy();
  const { data } = accountStore.useValue();
  const [query, setQuery] = useState('');
  const [showClosed, setShowClosed] = useState(false);
  const cardStyle = { ...styles.card, backgroundColor: theme.surface };
  const labelStyle = { color: theme.text };
  const captionStyle = { color: theme.textSecondary };
  const amountStyle = { ...styles.amount, color: theme.text };
  const portfolioKeys = new Set([...data.trades, ...data.bonds, ...data.fundHoldings].map(row => row.id));
  const search = query.trim().toLocaleLowerCase();
  const visible = state.investments.filter(row => (showClosed || !isClosedInvestment(row))
    && `${row.name} ${row.code} ${row.type} ${row.subtype}`.toLocaleLowerCase().includes(search));
  const connections = state.itemIDs.map(id => {
    const item = state.items.find(row => row.id === id);
    return <View key={id} style={cardStyle}>
      <Text style={labelStyle}>{institutionsOf(state, id) ?? item?.connector?.name ?? t('Connection')}</Text>
      <Text style={captionStyle}>{item?.status ?? t('Waiting for sync')}</Text>
    </View>;
  });
  const accounts = state.accounts.map(account => <View key={account.id} style={cardStyle}>
    <Text style={labelStyle}>{account.marketingName ?? account.name ?? t('Account')}</Text>
    <Text style={captionStyle}>{account.type} · {account.number}</Text>
    <Text style={amountStyle}>{money(account.balance, account.currencyCode ?? 'BRL')}</Text>
  </View>);
  const investments = visible.map(row => {
    const closed = isClosedInvestment(row);
    return <View key={row.id} style={cardStyle}>
      <Text style={labelStyle}>{row.name ?? row.code ?? t('Investment')}</Text>
      <Text style={captionStyle}>{row.type} · {row.subtype} · {row.code}</Text>
      <Text style={labelStyle}>{money(row.amount ?? row.balance, row.currencyCode ?? 'BRL')}</Text>
      <Text style={captionStyle}>{t('Quantity')}: {row.quantity?.toLocaleString() ?? '—'}</Text>
      <Text style={captionStyle}>{closed ? t('Closed') : portfolioKeys.has(investmentKey(row))
        ? t('Tracked in portfolio') : t('Review missing details')}</Text>
    </View>;
  });
  const imported = data.trades.filter(row => row.id.startsWith('pluggy-')).length
    + data.bonds.filter(row => row.id.startsWith('pluggy-')).length
    + data.fundHoldings.filter(row => row.id.startsWith('pluggy-')).length;
  return <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}
    refreshControl={<RefreshControl refreshing={state.isSyncing} onRefresh={() => void sync()} />}>
    <Text style={[styles.title, labelStyle]}>{t('Open Finance')}</Text>
    <Text style={captionStyle}>{t('Personal account · saved on this device.')}</Text>
    <Text style={captionStyle}>{state.lastSync ? `${t('Last sync')}: ${state.lastSync.toLocaleString()}` : t('Waiting for sync')}</Text>
    <Text style={captionStyle}>{t('Refreshes after 6 hours and when the app opens with stale data.')}</Text>
    <Text style={captionStyle}>{backgroundSyncAvailable
      ? t('Background refresh is managed by the operating system; timing may vary.')
      : t('Background refresh requires a native build on a physical device. Foreground refresh is active.')}</Text>
    <ActionButton title={t('Sync now')} isDisabled={state.isSyncing || !state.itemIDs.length} onPress={() => void sync()} />
    <Link href="/settings" style={{ color: theme.link }}>{t('Manage connections in Settings')}</Link>
    {state.error && <Text style={{ color: theme.warning }}>{state.error}</Text>}
    <Text style={[styles.heading, labelStyle]}>{t('Connections')}</Text>
    {connections}
    <Text style={[styles.heading, labelStyle]}>{t('Accounts')}</Text>
    {accounts.length ? accounts : <Text style={captionStyle}>{t('No accounts available yet.')}</Text>}
    <Text style={[styles.heading, labelStyle]}>{t('Investments')} · {state.investments.length}</Text>
    <Text style={captionStyle}>{t('{count} positions imported into your portfolio.', { count: imported })}</Text>
    <Text style={captionStyle}>{t('Positions with missing terms or fund identifiers remain here for review. No values are guessed.')}</Text>
    <TextInput accessibilityLabel={t('Search investments')} placeholder={t('Search investments')}
      placeholderTextColor={theme.textSecondary} value={query} onChangeText={setQuery} style={[styles.search, labelStyle]} />
    <ActionButton title={t(showClosed ? 'Hide closed positions' : 'Show closed positions')} onPress={() => setShowClosed(!showClosed)} />
    {investments}
  </ScrollView>;
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 12, paddingBottom: 40 },
  title: { fontSize: 28, fontWeight: '700' },
  heading: { fontSize: 20, fontWeight: '600', marginTop: 12 },
  card: { borderRadius: 12, padding: 16, gap: 6 },
  amount: { fontSize: 18, fontWeight: '600' },
  search: { minHeight: 48, borderWidth: StyleSheet.hairlineWidth, borderRadius: 8, paddingHorizontal: 12 },
});
