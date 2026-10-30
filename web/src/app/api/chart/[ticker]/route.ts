import { cacheLife } from "next/cache";
import { NextResponse, type NextRequest } from "next/server";
import brStocks from "@/data/assets/br-stocks.json";
import fiis from "@/data/assets/fiis.json";
import usETFs from "@/data/assets/us-etfs.json";

// Prices for the chart on each asset page, from Yahoo Finance (which the browser can't call: no CORS). Only tickers
// that have a page, so this isn't an open proxy. B3 quotes on Yahoo are delayed by about 15 minutes.

export type ChartRange = "1d" | "5d" | "1mo" | "6mo" | "1y" | "5y";

export type ChartData = {
  ticker: string;
  currency: string;
  price: number;
  /** The close before the range starts: the change shown is against it. */
  previousClose: number;
  /** Seconds since 1970 of the last trade. */
  marketTime: number;
  /** Whether the exchange is in its regular session now. */
  open: boolean;
  /** Offset of the exchange's time zone from UTC, in seconds (São Paulo: -10800). */
  gmtOffset: number;
  points: [time: number, close: number][];
};

const intervals: Record<ChartRange, string> = { "1d": "2m", "5d": "15m", "1mo": "60m", "6mo": "1d", "1y": "1d", "5y": "1wk" };

const symbols = new Map<string, string>([
  ...brStocks.assets.map((a) => [a.ticker, `${a.ticker}.SA`] as const),
  ...fiis.assets.map((a) => [a.ticker, `${a.ticker}.SA`] as const),
  ...usETFs.assets.map((a) => [a.ticker, a.ticker] as const),
]);

async function chart(ticker: string, symbol: string, range: ChartRange): Promise<ChartData | null> {
  "use cache";
  // Intraday ranges refresh often; daily and weekly bars hardly change during a session.
  cacheLife(range === "1d" ? { stale: 15, revalidate: 15, expire: 120 } : range === "5d" ? { stale: 60, revalidate: 60, expire: 600 } : { stale: 600, revalidate: 600, expire: 3600 });
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=${range}&interval=${intervals[range]}&includePrePost=false`;
  const response = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
  if (!response.ok) return null;
  const result = (await response.json()).chart?.result?.[0];
  if (!result?.timestamp) return null;
  const { meta } = result;
  const closes: (number | null)[] = result.indicators.quote[0].close;
  const points = (result.timestamp as number[])
    .map((t, i) => [t, closes[i]] as [number, number | null])
    .filter((p): p is [number, number] => p[1] != null);
  const session = meta.currentTradingPeriod?.regular;
  const now = Math.floor(Date.now() / 1000);
  return {
    ticker,
    currency: meta.currency,
    price: meta.regularMarketPrice,
    previousClose: meta.chartPreviousClose ?? meta.previousClose ?? points[0]?.[1],
    marketTime: meta.regularMarketTime,
    open: session ? now >= session.start && now < session.end : false,
    gmtOffset: meta.gmtoffset ?? 0,
    points,
  };
}

export async function GET(request: NextRequest, { params }: RouteContext<"/api/chart/[ticker]">) {
  const ticker = (await params).ticker.toUpperCase();
  const symbol = symbols.get(ticker);
  const range = (request.nextUrl.searchParams.get("range") ?? "1d") as ChartRange;
  if (!symbol || !(range in intervals)) return NextResponse.json({ error: "unknown ticker or range" }, { status: 404 });
  const data = await chart(ticker, symbol, range);
  if (!data) return NextResponse.json({ error: "prices unavailable" }, { status: 502 });
  return NextResponse.json(data, { headers: { "Cache-Control": `public, s-maxage=${range === "1d" ? 15 : 60}, stale-while-revalidate=60` } });
}
