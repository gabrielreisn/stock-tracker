import { router } from 'expo-router';
import { useState } from 'react';
import {
  Pressable,
  RefreshControl,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Metric, ReturnMetric } from '@/components/funds/ui';
import { styles } from '@/components/funds/styles';
import { ActionButton } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import {
  fundStore,
  formatCNPJ,
  fundPurpose,
  money,
  purposeLabels,
  purposes,
  shares,
  dayInput,
} from '@/lib/funds';
import { t } from '@/lib/i18n';
import { fundValuation, weightedFundReturn } from '@/lib/fund-performance';
import { refreshFundMarket, useFundMarket } from '@/lib/use-fund-market';
import { isConfigured, sync, usePluggy } from '@/lib/pluggy-store';
import type { FundHolding } from '@/types';

const sortOptions = ['Name', 'Shares', 'Gross value'] as const;
type Sort = (typeof sortOptions)[number];
const palette = [
  '#2a78d6',
  '#eb6834',
  '#1baf7a',
  '#eda100',
  '#e87ba4',
  '#7e4fd6',
];

export default function FundsScreen() {
  const theme = useTheme();
  const { holdings } = fundStore.useValue();
  const market = useFundMarket(holdings);
  const pluggy = usePluggy();
  const [refreshing, setRefreshing] = useState(false);
  const [syncFailed, setSyncFailed] = useState(false);
  const valuations = holdings.map((fund) =>
    fundValuation(fund, market.histories[fund.cnpj]),
  );
  function grossValue(fund: FundHolding) {
    return fundValuation(fund, market.histories[fund.cnpj])?.gross;
  }
  function refresh() {
    if (refreshing) return;
    setRefreshing(true);
    setSyncFailed(false);
    void reloadFundData(isConfigured(pluggy) && pluggy.itemIDs.length > 0)
      .then(
        (success) => setSyncFailed(!success),
        () => setSyncFailed(true),
      )
      .finally(() => setRefreshing(false));
  }
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<Sort>('Gross value');
  const [ascending, setAscending] = useState(false);
  const valued = holdings.filter((fund) => grossValue(fund) !== undefined);
  const total = valued.reduce((sum, fund) => sum + grossValue(fund)!, 0);
  const complete = valued.length === holdings.length;
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const rows = holdings
    .filter(
      (fund) =>
        fund.name.toLocaleLowerCase().includes(normalizedQuery) ||
        formatCNPJ(fund.cnpj).includes(normalizedQuery) ||
        fund.cnpj.includes(normalizedQuery),
    )
    .sort((a, b) => {
      const direction = ascending ? 1 : -1;
      if (sort === 'Name') return direction * a.name.localeCompare(b.name);
      const av = sort === 'Shares' ? a.quantity : grossValue(a);
      const bv = sort === 'Shares' ? b.quantity : grossValue(b);
      if (av === undefined)
        return bv === undefined ? a.name.localeCompare(b.name) : 1;
      if (bv === undefined) return -1;
      return direction * (av - bv) || a.name.localeCompare(b.name);
    });
  const cards = rows.map((fund) => {
    const value = fundValuation(fund, market.histories[fund.cnpj]);
    const price = value?.price;
    const source = value?.source;
    return (
      <Pressable
        key={fund.id}
        accessibilityRole="button"
        accessibilityLabel={`${t('Edit fund')}: ${fund.name}`}
        onPress={() =>
          router.push({
            pathname: '/investments/funds/[id]',
            params: { id: fund.id },
          })
        }
        style={[styles.card, { backgroundColor: theme.surface }]}
      >
        <Text style={[styles.name, { color: theme.text }]}>{fund.name}</Text>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>
          {formatCNPJ(fund.cnpj)} · {fund.kind.toUpperCase()} ·{' '}
          {t(fund.taxExempt ? 'Tax exempt' : 'Taxable')}
        </Text>
        <Text style={[styles.caption, { color: theme.link }]}>
          {t(purposeLabels[fundPurpose(fund)])}
        </Text>
        <View style={styles.wrap}>
          <Metric label={t('Shares')} value={shares(fund.quantity)} />
          <Metric label={t('Gross value')} value={money(grossValue(fund))} />
          <Metric
            label={t('Share price')}
            value={price === undefined ? '—' : shares(price)}
          />
          <Metric
            label={t('Price date')}
            value={value ? dayInput(value.day) : '—'}
          />
        </View>
        {source && (
          <Text style={[styles.caption, { color: theme.textSecondary }]}>
            {t(source)}
          </Text>
        )}
        <View style={styles.row}>
          <ReturnMetric label={t('Last month')} value={value?.month} />
          <ReturnMetric label={t('Year to date')} value={value?.ytd} />
          <ReturnMetric label={t('Last 12 months')} value={value?.year} />
        </View>
        {value?.returnDay && (
          <Text style={[styles.caption, { color: theme.textSecondary }]}>
            {t('CVM returns as of {date}', { date: dayInput(value.returnDay) })}
          </Text>
        )}
        <Text style={[styles.caption, { color: theme.link }]}>
          {t('Edit fund')} →
        </Text>
      </Pressable>
    );
  });
  const sortButtons = sortOptions.map((option) => (
    <Pressable
      key={option}
      accessibilityRole="button"
      accessibilityState={{ selected: sort === option }}
      onPress={() => {
        setSort(option);
        setAscending(option === 'Name');
      }}
      style={[
        styles.chip,
        { backgroundColor: sort === option ? theme.selected : theme.surface },
      ]}
    >
      <Text style={{ color: theme.text }}>{t(option)}</Text>
    </Pressable>
  ));
  const groups = purposes.map((purpose, index) => {
    const funds = valued
      .filter((fund) => fundPurpose(fund) === purpose)
      .sort((a, b) => grossValue(b)! - grossValue(a)!);
    if (!funds.length) return null;
    const gross = funds.reduce((sum, fund) => sum + grossValue(fund)!, 0);
    const percent = (gross / total) * 100;
    const fundNames = funds.map((fund) => (
      <Text
        key={fund.id}
        style={[styles.caption, { color: theme.textSecondary }]}
      >
        {fund.name} · {money(grossValue(fund))}
      </Text>
    ));
    return (
      <View key={purpose} style={{ gap: 8 }}>
        <View style={styles.row}>
          <Text style={[styles.name, { color: theme.text, flex: 1 }]}>
            {t(purposeLabels[purpose])}
          </Text>
          <Text style={{ color: theme.text }}>
            {percent.toFixed(1)}% · {money(gross)}
          </Text>
        </View>
        <View style={[styles.bar, { backgroundColor: theme.selected }]}>
          <View
            style={{
              height: 8,
              width: `${percent}%`,
              backgroundColor: palette[index],
            }}
          />
        </View>
        {fundNames}
      </View>
    );
  });
  return (
    <ScrollView
      refreshControl={
        <RefreshControl
          refreshing={refreshing || market.loading}
          onRefresh={() => void refresh()}
          tintColor={theme.textSecondary}
        />
      }
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={styles.content}
      style={{ backgroundColor: theme.background }}
    >
      <View style={styles.row}>
        <Text style={[styles.title, { color: theme.text }]}>
          {t('Your funds')}
        </Text>
        <ActionButton
          title={t('Add fund')}
          onPress={() => router.push('/investments/funds/new')}
          isPrimary
        />
      </View>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>
        {t('Personal account · saved on this device.')}
      </Text>
      <View style={[styles.card, { backgroundColor: theme.surface }]}>
        <View style={styles.wrap}>
          <Metric
            label={t(complete ? 'Gross value' : 'Known gross value')}
            value={money(valued.length ? total : undefined)}
          />
          <ReturnMetric
            label={t('Last month')}
            value={weightedFundReturn(valuations, 'month')}
          />
          <ReturnMetric
            label={t('Year to date')}
            value={weightedFundReturn(valuations, 'ytd')}
          />
          <ReturnMetric
            label={t('Last 12 months')}
            value={weightedFundReturn(valuations, 'year')}
          />
        </View>
        <Text style={[styles.caption, { color: theme.textSecondary }]}>
          {t('{count} of {total} funds valued', {
            count: valued.length,
            total: holdings.length,
          })}
        </Text>
      </View>
      {market.loading && (
        <Text style={[styles.caption, { color: theme.textSecondary }]}>
          {t('Loading CVM reports {done}/{total}', {
            done: market.done,
            total: market.total,
          })}
        </Text>
      )}
      {!!market.failed.length && (
        <Text
          accessibilityRole="alert"
          style={[styles.caption, { color: theme.warning }]}
        >
          {t(
            'Some CVM reports could not be refreshed. Cached prices remain visible. Pull to retry.',
          )}
        </Text>
      )}
      {syncFailed && (
        <Text
          accessibilityRole="alert"
          style={[styles.caption, { color: theme.warning }]}
        >
          {t(
            'Bank holdings could not be refreshed. Previous holdings remain visible.',
          )}
        </Text>
      )}
      <TextInput
        accessibilityLabel={t('Search by name or CNPJ')}
        placeholder={t('Search by name or CNPJ')}
        placeholderTextColor={theme.textSecondary}
        value={query}
        onChangeText={setQuery}
        style={[
          styles.input,
          { color: theme.text, borderColor: theme.selected },
        ]}
      />
      <View style={styles.wrap}>
        {sortButtons}
        <ActionButton
          title={t(ascending ? 'Ascending' : 'Descending')}
          onPress={() => setAscending(!ascending)}
        />
      </View>
      {cards}
      {!holdings.length && (
        <Text style={{ color: theme.textSecondary }}>
          {t('No funds yet. Add a fund to get started.')}
        </Text>
      )}
      {!!holdings.length && !rows.length && (
        <Text style={{ color: theme.textSecondary }}>
          {t('No matching funds.')}
        </Text>
      )}
      <View style={[styles.card, { backgroundColor: theme.surface }]}>
        <Text
          accessibilityRole="header"
          style={[styles.title, { color: theme.text }]}
        >
          {t('Allocation by purpose')}
        </Text>
        {total > 0 ? (
          groups
        ) : (
          <Text style={[styles.caption, { color: theme.textSecondary }]}>
            {t('Add statement prices to see allocation by value.')}
          </Text>
        )}
        {!complete && (
          <Text style={[styles.caption, { color: theme.textSecondary }]}>
            {t('Funds without prices are excluded from allocation.')}
          </Text>
        )}
      </View>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>
        {t(
          'Prices use CVM or a newer statement. Returns use CVM history as of its latest quote: daily for FIFs, monthly for FIDCs. FIPs have no public quota history. Missing periods show —. Summary returns are weighted by known gross value. Values are before income tax. Pull to refresh.',
        )}
      </Text>
    </ScrollView>
  );
}

async function reloadFundData(refreshBank: boolean): Promise<boolean> {
  let success = true;
  if (refreshBank) {
    try {
      success = await sync();
    } catch {
      success = false;
    }
  }
  await refreshFundMarket(fundStore.get().holdings, true);
  return success;
}
