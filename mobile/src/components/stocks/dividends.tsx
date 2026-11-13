import { useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { Card, Choices, Label, Title } from "@/components/bonds/ui";
import { useTheme } from "@/hooks/use-theme";
import { language, t, type StringKey } from "@/lib/i18n";
import {
  dividendPaid,
  dividendPayments,
  dividendSummary,
} from "@/lib/stock-dividends";
import type {
  DividendKind,
  DividendPayment,
  StockDividend,
  StockHolding,
  StockQuote,
} from "@/types/stocks";

const locale = language === "pt" ? "pt-BR" : "en-US";
const money = (value?: number) =>
  value === undefined
    ? "—"
    : value.toLocaleString(locale, { style: "currency", currency: "BRL" });
const number = (value: number) =>
  value.toLocaleString(locale, { maximumFractionDigits: 6 });
const kinds: DividendKind[] = ["dividend", "jcp", "income"];
const kindLabels: Record<DividendKind, StringKey> = {
  dividend: "Dividend",
  jcp: "JCP",
  income: "Income distribution",
};
const filters = ["All payments", "Received", "Upcoming"] as const;
function date(day: number) {
  return new Date(
    Math.floor(day / 10000),
    (Math.floor(day / 100) % 100) - 1,
    day % 100,
  ).toLocaleDateString(locale);
}
function PaymentRow({
  payment,
  today,
}: {
  payment: DividendPayment;
  today: number;
}) {
  const theme = useTheme();
  const colors = {
    dividend: theme.link,
    jcp: theme.warning,
    income: theme.success,
  };
  const p = payment;
  const paid = dividendPaid(p, today);
  const mainDate = p.datedByExDate
    ? date(p.recordDay)
    : p.paymentDay
      ? date(p.paymentDay)
      : t("Payment date not set");
  const record = p.datedByExDate
    ? t("Ex-date")
    : `${t("Holders on")} ${date(p.recordDay)}`;
  return (
    <View style={[styles.payment, { borderBottomColor: theme.selected }]}>
      <View style={styles.row}>
        <Title>{p.ticker}</Title>
        <Text style={[styles.amount, { color: theme.text }]}>
          {money(p.amount)}
        </Text>
      </View>
      <View style={styles.row}>
        <Label>{mainDate}</Label>
        <Text
          style={[
            styles.tag,
            { color: colors[p.kind], borderColor: colors[p.kind] },
          ]}
        >
          {t(kindLabels[p.kind])}
        </Text>
      </View>
      <View style={styles.row}>
        <Label secondary>{record}</Label>
        {!paid && <Text style={{ color: theme.warning }}>{t("Upcoming")}</Text>}
      </View>
      <Label secondary>
        {number(p.quantity)} × {number(p.perShare)}{" "}
        {p.ticker.match(/\d$/) ? "BRL" : "USD"}
      </Label>
    </View>
  );
}
function MonthlyChart({
  payments,
  today,
}: {
  payments: DividendPayment[];
  today: number;
}) {
  const theme = useTheme();
  const colors = {
    dividend: theme.link,
    jcp: theme.warning,
    income: theme.success,
  };
  const year = Math.floor(today / 10000);
  const monthly = Array.from({ length: 12 }, (_, index) =>
    payments.filter(
      (p) =>
        Math.floor((p.paymentDay ?? p.recordDay) / 100) ===
        year * 100 + index + 1,
    ),
  );
  const totals = monthly.map((rows) =>
    rows.reduce((sum, p) => sum + (p.amount ?? 0), 0),
  );
  const max = Math.max(1, ...totals);
  const bars = monthly.map((rows, month) => {
    const slices = kinds.flatMap((kind) =>
      [true, false].map((paid) => {
        const amount = rows
          .filter((p) => p.kind === kind && dividendPaid(p, today) === paid)
          .reduce((sum, p) => sum + (p.amount ?? 0), 0);
        return (
          <View
            key={`${kind}-${paid}`}
            style={{
              height: (amount / max) * 120,
              backgroundColor: colors[kind],
              opacity: paid ? 1 : 0.4,
            }}
          />
        );
      }),
    );
    const label = new Date(year, month, 1).toLocaleDateString(locale, {
      month: "short",
    });
    return (
      <View
        key={month}
        style={styles.month}
        accessible
        accessibilityLabel={`${label}: ${money(totals[month])}`}
      >
        <Text style={[styles.chartAmount, { color: theme.textSecondary }]}>
          {totals[month] > 0
            ? Math.round(totals[month]).toLocaleString(locale)
            : ""}
        </Text>
        <View style={styles.stack}>{slices}</View>
        <Label secondary>{label}</Label>
      </View>
    );
  });
  const legend = kinds.map((kind) => (
    <Text key={kind} style={{ color: colors[kind] }}>
      ● {t(kindLabels[kind])}
    </Text>
  ));
  return (
    <>
      <Title>{t("Monthly dividends")}</Title>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={styles.chart}>{bars}</View>
      </ScrollView>
      <View style={styles.legend}>{legend}</View>
      <Label secondary>{t("Faded bars indicate upcoming payments.")}</Label>
    </>
  );
}
export function StockDividends({
  holdings,
  quotes,
  announcements,
  failures,
  loading,
}: {
  holdings: StockHolding[];
  quotes: Record<string, StockQuote>;
  announcements: Record<string, StockDividend[] | null>;
  failures: string[];
  loading: boolean;
}) {
  const [filter, setFilter] =
    useState<(typeof filters)[number]>("All payments");
  const now = new Date();
  const today =
    now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
  const year = now.getFullYear();
  const payments = dividendPayments(holdings, quotes, announcements, year);
  const summary = dividendSummary(payments, today);
  const available = payments.length > 0;
  const filtered = payments.filter(
    (p) =>
      filter === "All payments" ||
      dividendPaid(p, today) === (filter === "Received"),
  );
  const rows = filtered.map((p) => (
    <PaymentRow key={p.id} payment={p} today={today} />
  ));
  const missing = holdings
    .filter((h) => announcements[h.ticker] === undefined && !quotes[h.ticker])
    .map((h) => h.ticker);
  const incomplete =
    failures.length > 0 || missing.length > 0 || summary.missingFX;
  const received =
    available && !summary.missingFX ? money(summary.received) : "—";
  const upcoming =
    available && !summary.missingFX ? money(summary.upcoming) : "—";
  return (
    <Card>
      <Title>
        {t("Dividends")} · {year}
      </Title>
      <View style={styles.row}>
        <Label secondary>
          {t("Received in")} {year}
        </Label>
        <Label>{received}</Label>
      </View>
      <View style={styles.row}>
        <Label secondary>{t("Upcoming")}</Label>
        <Label>{upcoming}</Label>
      </View>
      {incomplete && (
        <Label secondary>
          {t("Partial dividend data. Totals include available events only.")}
        </Label>
      )}
      <Choices
        values={filters}
        selected={filter}
        onChange={setFilter}
        label={(value) => t(value)}
      />
      {rows.length > 0 ? (
        <ScrollView nestedScrollEnabled style={styles.list}>
          {rows}
        </ScrollView>
      ) : (
        <Label secondary>
          {t(loading ? "Loading dividends…" : "No payments in this view.")}
        </Label>
      )}
      <MonthlyChart payments={payments} today={today} />
      <Label secondary>
        {t(
          "Amounts use current shares, before tax. B3 companies use announced payment and record dates. ETFs and US holdings use Yahoo ex-dates; these do not confirm receipt. US amounts use historical USD/BRL.",
        )}
      </Label>
      {failures.length > 0 && (
        <Label secondary>
          {t(
            "B3 announcements unavailable; Yahoo ex-dates used when available.",
          )}
          : {failures.join(", ")}
        </Label>
      )}
    </Card>
  );
}
const styles = StyleSheet.create({
  row: {
    flexDirection: "row",
    justifyContent: "space-between",
    gap: 12,
    flexWrap: "wrap",
  },
  payment: {
    paddingVertical: 14,
    gap: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  amount: { fontSize: 17, fontWeight: "600", fontVariant: ["tabular-nums"] },
  tag: {
    fontSize: 12,
    fontWeight: "600",
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  list: { maxHeight: 420 },
  legend: { flexDirection: "row", flexWrap: "wrap", gap: 12 },
  chart: { flexDirection: "row", gap: 8, paddingTop: 8 },
  month: { width: 40, alignItems: "center", gap: 4 },
  stack: {
    height: 120,
    width: 24,
    justifyContent: "flex-end",
    overflow: "hidden",
    borderRadius: 3,
  },
  chartAmount: { fontSize: 10, height: 16, fontVariant: ["tabular-nums"] },
});
