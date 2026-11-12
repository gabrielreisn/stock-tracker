import { useState } from "react";
import {
  Alert,
  KeyboardAvoidingView,
  RefreshControl,
  ScrollView,
  StyleSheet,
  View,
} from "react-native";
import { Card, Choices, Label, Title } from "@/components/bonds/ui";
import { ActionButton } from "@/components/settings/ui";
import { StockDividends } from "@/components/stocks/dividends";
import { StockPerformance } from "@/components/stocks/performance";
import { StockForm } from "@/components/stocks/stock-form";
import { useTheme } from "@/hooks/use-theme";
import { removeStock, useStockTrades } from "@/lib/stock-store";
import { language, t, type StringKey } from "@/lib/i18n";
import { percent } from "@/lib/stock-performance";
import {
  holdingMetrics,
  isB3Stock,
  sortStocks,
  stockCurrency,
  stockHoldings,
} from "@/lib/stocks";
import { refreshStockMarket, useStockMarket } from "@/lib/use-stock-market";
import type { StockHolding, StockQuote, StockSort } from "@/types/stocks";

const sorts: StockSort[] = [
  "ticker",
  "shares",
  "average",
  "price",
  "value",
  "gain",
  "today",
  "ytd",
];
const sortLabels: Record<StockSort, StringKey> = {
  ticker: "Ticker",
  shares: "Shares",
  average: "Average price",
  price: "Price",
  value: "Value",
  gain: "Gain",
  today: "Today",
  ytd: "YTD",
};
function money(value: number | undefined, currency = "BRL") {
  return value === undefined
    ? "—"
    : value.toLocaleString(language === "pt" ? "pt-BR" : "en-US", {
        style: "currency",
        currency,
      });
}
function HoldingCard({
  holding,
  quotes,
}: {
  holding: StockHolding;
  quotes: Record<string, StockQuote>;
}) {
  const [editing, setEditing] = useState(false);
  const h = holding,
    quote = quotes[h.ticker],
    metrics = holdingMetrics(h, quotes);
  const currency = stockCurrency(h.ticker);
  const gainMoney =
    metrics.price !== undefined && h.averagePrice !== undefined
      ? (metrics.price - h.averagePrice) * h.quantity
      : undefined;
  const fields = [
    [t("Shares"), h.quantity.toLocaleString()],
    [t("Average price"), money(h.averagePrice, currency)],
    [t("Price"), money(metrics.price, currency)],
    [t("Value"), money(metrics.value)],
    [t("Gain"), `${percent(metrics.gain)} · ${money(gainMoney, currency)}`],
    [t("Today"), percent(metrics.today)],
    [t("YTD"), percent(metrics.ytd)],
  ];
  const details = fields.map(([label, value]) => (
    <View key={label} style={styles.row}>
      <Label secondary>{label}</Label>
      <Label>{value}</Label>
    </View>
  ));
  function remove() {
    Alert.alert(t("Remove stock?"), h.ticker, [
      { text: t("Cancel"), style: "cancel" },
      {
        text: t("Remove"),
        style: "destructive",
        onPress: () => removeStock(h.ticker),
      },
    ]);
  }
  return (
    <Card>
      <Title>
        {h.ticker} · {isB3Stock(h.ticker) ? "B3" : "US"}
      </Title>
      {quote?.history.name && <Label secondary>{quote.history.name}</Label>}
      {editing ? (
        <StockForm
          holding={h}
          inline
          onClose={() => setEditing(false)}
          onSaved={() => setEditing(false)}
        />
      ) : (
        details
      )}
      {quote?.asOf && (
        <Label secondary>
          {t("Price as of")} {new Date(quote.asOf).toLocaleString()}
        </Label>
      )}
      {!editing && (
        <View style={styles.actions}>
          <ActionButton
            title={t("Edit stock")}
            onPress={() => setEditing(true)}
          />
          <ActionButton title={t("Remove")} onPress={remove} />
        </View>
      )}
    </Card>
  );
}
export function StocksScreen() {
  const theme = useTheme();
  const holdings = stockHoldings(useStockTrades());
  const tickers = holdings.map((h) => h.ticker).sort();
  const market = useStockMarket(tickers);
  const [editor, setEditor] = useState(false);
  const [sort, setSort] = useState<StockSort>("value");
  const [ascending, setAscending] = useState(false);
  const rows = sortStocks(holdings, market.quotes, sort, ascending);
  const metrics = holdings.map((h) => holdingMetrics(h, market.quotes));
  const complete =
    holdings.length > 0 && metrics.every((m) => m.value !== undefined);
  const total = complete
    ? metrics.reduce((sum, m) => sum + m.value!, 0)
    : undefined;
  const b3 = holdings.filter(
    (h) => isB3Stock(h.ticker) && h.averagePrice !== undefined,
  );
  const cost = b3.reduce((sum, h) => sum + h.quantity * h.averagePrice!, 0);
  const b3Value = b3.every((h) => market.quotes[h.ticker]?.price !== undefined)
    ? b3.reduce(
        (sum, h) => sum + h.quantity * market.quotes[h.ticker].price!,
        0,
      )
    : undefined;
  const cards = rows.map((h) => (
    <HoldingCard key={h.ticker} holding={h} quotes={market.quotes} />
  ));
  function refresh() {
    void refreshStockMarket(tickers);
  }
  function saved() {
    setEditor(false);
  }
  return (
    <KeyboardAvoidingView
      behavior="padding"
      style={[styles.root, { backgroundColor: theme.background }]}
    >
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={styles.root}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl refreshing={market.loading} onRefresh={refresh} />
        }
      >
        <Label secondary>{t("Personal account · saved on this device.")}</Label>
        <Card>
          <Title>
            {t("Stocks")} · {holdings.length}
          </Title>
          <Label>
            {t("Total value")}: {money(total)}
          </Label>
          <Label secondary>
            {t(
              "Quotes may be delayed. Pull to refresh. Missing prices are excluded from totals by showing —.",
            )}
          </Label>
          {market.failed.length > 0 && (
            <>
              <Label secondary>
                {t(
                  "Some market data could not be refreshed. Previous quotes, if any, remain visible.",
                )}
                : {market.failed.join(", ")}
              </Label>
              <ActionButton
                title={t("Retry")}
                onPress={refresh}
                isDisabled={market.loading}
              />
            </>
          )}
          <ActionButton
            title={t("Add stock")}
            onPress={() => setEditor(true)}
          />
        </Card>
        {editor && (
          <StockForm onClose={() => setEditor(false)} onSaved={saved} />
        )}
        <StockPerformance
          holdings={holdings}
          quotes={market.quotes}
          rates={market.rates}
        />
        <Title>{t("Holdings")}</Title>
        {cost > 0 && (
          <Card>
            <Label>
              B3 · {t("Cost")}: {money(cost)}
            </Label>
            <Label>
              {t("Value")}: {money(b3Value)}
            </Label>
            <Label>
              {t("Gain")}:{" "}
              {money(b3Value === undefined ? undefined : b3Value - cost)} ·{" "}
              {percent(b3Value === undefined ? undefined : b3Value / cost - 1)}
            </Label>
          </Card>
        )}
        <Choices
          values={sorts}
          selected={sort}
          onChange={(value) => {
            setSort(value);
            setAscending(value === "ticker");
          }}
          label={(value) => t(sortLabels[value])}
        />
        <ActionButton
          title={t(ascending ? "Ascending ↑" : "Descending ↓")}
          onPress={() => setAscending((value) => !value)}
        />
        {holdings.length ? (
          cards
        ) : (
          <Card>
            <Label secondary>
              {t("No stocks yet. Add a ticker and quantity.")}
            </Label>
          </Card>
        )}
        <StockDividends
          holdings={holdings}
          quotes={market.quotes}
          announcements={market.announcements}
          failures={market.dividendFailures}
          loading={market.loading}
        />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16 },
  row: { flexDirection: "row", justifyContent: "space-between", gap: 12 },
  actions: { flexDirection: "row", gap: 12 },
});
