import type {
  DividendPayment,
  StockDividend,
  StockHolding,
  StockQuote,
} from "@/types/stocks";
import { closeBefore, isB3Stock } from "@/lib/stocks";

interface CashDividend {
  isinCode?: string;
  label?: string;
  rate?: string;
  paymentDate?: string;
  lastDatePrior?: string;
}
function parseDate(value?: string) {
  const parts = value?.split("/").map(Number);
  if (!parts || parts.length !== 3) return undefined;
  const [day, month, year] = parts;
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
    ? year * 10000 + month * 100 + day
    : undefined;
}
const shareClasses: Record<string, string> = {
  "3": "ACNOR",
  "4": "ACNPR",
  "5": "ACNPA",
  "6": "ACNPB",
  "11": "UNT",
};
export function parseB3Dividends(
  ticker: string,
  cash: CashDividend[],
): StockDividend[] | null {
  const company = ticker.slice(0, 4),
    shareClass = shareClasses[ticker.slice(4)];
  if (!shareClass) return null;
  const rows = cash.flatMap((row) => {
    const recordDay = parseDate(row.lastDatePrior);
    const perShare = Number(row.rate?.replaceAll(".", "").replace(",", "."));
    if (
      !row.isinCode?.startsWith(`BR${company}${shareClass}`) ||
      !recordDay ||
      !Number.isFinite(perShare) ||
      perShare <= 0
    )
      return [];
    const kind: StockDividend["kind"] = row.label?.includes("JRS")
      ? "jcp"
      : row.label?.includes("REND")
        ? "income"
        : "dividend";
    return [
      { kind, recordDay, paymentDay: parseDate(row.paymentDate), perShare },
    ];
  });
  return rows.length ? rows : null;
}
export async function fetchB3Dividends(
  ticker: string,
  signal: AbortSignal,
): Promise<StockDividend[] | null> {
  if (!isB3Stock(ticker) || !shareClasses[ticker.slice(4)]) return null;
  const query = btoa(
    JSON.stringify({ language: "pt-br", issuingCompany: ticker.slice(0, 4) }),
  );
  const response = await fetch(
    `https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/GetListedSupplementCompany/${query}`,
    { signal, headers: { "User-Agent": "Mozilla/5.0" } },
  );
  if (!response.ok) throw new Error("B3 announcements unavailable");
  const data: unknown = await response.json();
  if (!Array.isArray(data)) throw new Error("Invalid B3 announcements");
  return parseB3Dividends(ticker, data[0]?.cashDividends ?? []);
}
export function dividendPayments(
  holdings: StockHolding[],
  quotes: Record<string, StockQuote>,
  announcements: Record<string, StockDividend[] | null>,
  year: number,
): DividendPayment[] {
  const payments = holdings.flatMap((h) => {
    const announced = announcements[h.ticker];
    const datedByExDate = !announced;
    const events: StockDividend[] =
      announced ??
      (quotes[h.ticker]?.history.dividends ?? []).map((d) => ({
        recordDay: d.day,
        perShare: d.amount,
        kind: isB3Stock(h.ticker) ? "income" : "dividend",
      }));
    return events
      .filter(
        (event) => (event.paymentDay ?? event.recordDay) >= year * 10000 + 101,
      )
      .map((event) => {
        const fx = isB3Stock(h.ticker)
          ? 1
          : closeBefore(quotes["BRL=X"]?.history, event.recordDay);
        return {
          ...event,
          id: `${h.ticker}-${event.kind}-${event.recordDay}-${event.paymentDay}-${event.perShare}`,
          ticker: h.ticker,
          quantity: h.quantity,
          amount:
            fx === undefined ? undefined : event.perShare * h.quantity * fx,
          datedByExDate,
        };
      });
  });
  return payments.sort(
    (a, b) =>
      (b.paymentDay ?? b.recordDay) - (a.paymentDay ?? a.recordDay) ||
      b.ticker.localeCompare(a.ticker),
  );
}
export function dividendPaid(payment: DividendPayment, today: number) {
  return payment.datedByExDate
    ? payment.recordDay <= today
    : payment.paymentDay !== undefined && payment.paymentDay <= today;
}
export function dividendSummary(payments: DividendPayment[], today: number) {
  const year = Math.floor(today / 10000);
  const received = payments.filter(
    (p) =>
      dividendPaid(p, today) &&
      Math.floor((p.paymentDay ?? p.recordDay) / 10000) === year,
  );
  const upcoming = payments.filter((p) => !dividendPaid(p, today));
  return {
    received: received.reduce((sum, p) => sum + (p.amount ?? 0), 0),
    upcoming: upcoming.reduce((sum, p) => sum + (p.amount ?? 0), 0),
    missingFX: payments.some((p) => p.amount === undefined),
  };
}
