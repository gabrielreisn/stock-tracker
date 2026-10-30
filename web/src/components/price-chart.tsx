"use client";

import { BaselineSeries, ColorType, createChart, type IChartApi, type ISeriesApi, type UTCTimestamp } from "lightweight-charts";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { ChartData, ChartRange } from "@/app/api/chart/[ticker]/route";

// The price chart on each asset page: today's session by default (refreshed every 30 seconds while the exchange is
// open and the tab is visible), or a longer period. The line is green above the previous close and red below it.

const ranges: { range: ChartRange; label: string }[] = [
  { range: "1d", label: "1D" },
  { range: "5d", label: "5D" },
  { range: "1mo", label: "1M" },
  { range: "6mo", label: "6M" },
  { range: "1y", label: "1A" },
  { range: "5y", label: "5A" },
];
const refreshSeconds = 30;
const symbols: Record<string, string> = { BRL: "R$", USD: "US$" };

const number = (x: number, digits = 2) => x.toLocaleString("pt-BR", { minimumFractionDigits: digits, maximumFractionDigits: digits });

/** Light or dark, following the system like the rest of the site. */
function usePrefersDark() {
  return useSyncExternalStore(
    (changed) => {
      const query = window.matchMedia("(prefers-color-scheme: dark)");
      query.addEventListener("change", changed);
      return () => query.removeEventListener("change", changed);
    },
    () => window.matchMedia("(prefers-color-scheme: dark)").matches,
    () => false,
  );
}

export function PriceChart({ ticker }: { ticker: string }) {
  const container = useRef<HTMLDivElement>(null);
  const chart = useRef<IChartApi | null>(null);
  const series = useRef<ISeriesApi<"Baseline"> | null>(null);
  const [range, setRange] = useState<ChartRange>("1d");
  const [data, setData] = useState<ChartData | null>(null);
  const [failed, setFailed] = useState(false);
  const dark = usePrefersDark();

  // Fetch the range, then keep today's session fresh while the market is open.
  useEffect(() => {
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    async function load() {
      try {
        const response = await fetch(`/api/chart/${ticker}?range=${range}`);
        if (!response.ok) throw new Error(String(response.status));
        const next: ChartData = await response.json();
        if (cancelled) return;
        setData(next);
        setFailed(false);
        if (range === "1d" && next.open) timer = setTimeout(tick, refreshSeconds * 1000);
      } catch {
        if (!cancelled) setFailed(true);
      }
    }
    function tick() {
      if (document.visibilityState === "visible") load();
      else timer = setTimeout(tick, refreshSeconds * 1000);
    }
    load();
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [ticker, range]);

  // The chart itself, created once and restyled with the theme.
  useEffect(() => {
    if (!container.current) return;
    const created = createChart(container.current, {
      autoSize: true,
      handleScroll: false,
      handleScale: false,
      layout: { background: { type: ColorType.Solid, color: "transparent" }, fontFamily: "inherit", fontSize: 12 },
      rightPriceScale: { borderVisible: false },
      timeScale: { borderVisible: false, fixLeftEdge: true, fixRightEdge: true },
      crosshair: { horzLine: { labelVisible: true }, vertLine: { labelVisible: true } },
      localization: { locale: "pt-BR", priceFormatter: (p: number) => number(p) },
    });
    series.current = created.addSeries(BaselineSeries, { lineWidth: 2, priceLineVisible: false });
    chart.current = created;
    return () => {
      created.remove();
      chart.current = null;
      series.current = null;
    };
  }, []);

  useEffect(() => {
    chart.current?.applyOptions({
      layout: { textColor: dark ? "#a1a1aa" : "#71717a" },
      grid: { vertLines: { visible: false }, horzLines: { color: dark ? "#27272a" : "#f4f4f5" } },
    });
    series.current?.applyOptions({
      topLineColor: "#059669",
      topFillColor1: "rgba(5, 150, 105, 0.22)",
      topFillColor2: "rgba(5, 150, 105, 0.02)",
      bottomLineColor: "#dc2626",
      bottomFillColor1: "rgba(220, 38, 38, 0.02)",
      bottomFillColor2: "rgba(220, 38, 38, 0.22)",
    });
  }, [dark]);

  useEffect(() => {
    if (!data || !series.current || !chart.current) return;
    // The chart shows times in UTC; shifting by the exchange's offset makes its axis read in local market time.
    series.current.setData(data.points.map(([t, close]) => ({ time: (t + data.gmtOffset) as UTCTimestamp, value: close })));
    series.current.applyOptions({ baseValue: { type: "price", price: data.previousClose } });
    chart.current.applyOptions({ timeScale: { timeVisible: range === "1d" || range === "5d" || range === "1mo", secondsVisible: false } });
    chart.current.timeScale().fitContent();
  }, [data, range]);

  const change = data ? data.price - data.previousClose : 0;
  const changePercent = data && data.previousClose ? change / data.previousClose : 0;
  const up = change >= 0;
  const updated = data
    ? new Date((data.marketTime + data.gmtOffset) * 1000).toLocaleString("pt-BR", { timeZone: "UTC", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })
    : null;
  // Over a period the change is the price alone; the page's returns include dividends.
  const periodLabel = range === "1d" ? "hoje" : `em ${ranges.find((r) => r.range === range)?.label}, só a cotação`;

  return (
    <section aria-label={`Gráfico de preço de ${ticker}`} className="rounded-2xl border border-zinc-200 p-4 sm:p-5 dark:border-zinc-800">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="text-3xl font-semibold tabular-nums">
            {data ? `${symbols[data.currency] ?? data.currency} ${number(data.price)}` : "—"}
          </div>
          {data && (
            <div className={`mt-1 text-sm font-medium tabular-nums ${up ? "text-emerald-600 dark:text-emerald-400" : "text-red-600 dark:text-red-400"}`}>
              {up ? "+" : ""}{number(change)} ({up ? "+" : ""}{number(changePercent * 100)}%) {periodLabel}
            </div>
          )}
        </div>
        <div role="tablist" className="flex gap-1 rounded-lg bg-zinc-100 p-1 text-sm dark:bg-zinc-900">
          {ranges.map((r) => (
            <button
              key={r.range}
              role="tab"
              aria-selected={range === r.range}
              onClick={() => setRange(r.range)}
              className={`rounded-md px-2.5 py-1 font-medium ${range === r.range ? "bg-white shadow-sm dark:bg-zinc-700" : "text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"}`}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      <div className="relative mt-4 h-72">
        <div ref={container} className="absolute inset-0" />
        {failed && !data && (
          <div className="absolute inset-0 flex items-center justify-center text-sm text-zinc-500">Cotações indisponíveis no momento.</div>
        )}
      </div>

      {data && (
        <p className="mt-3 flex items-center gap-2 text-xs text-zinc-500">
          <span className={`size-2 rounded-full ${data.open ? "bg-emerald-500" : "bg-zinc-400"}`} />
          {data.open ? "Mercado aberto" : "Mercado fechado"} · última cotação {updated}
          {data.currency === "BRL" ? " (horário de Brasília), com atraso de cerca de 15 minutos" : " (horário de Nova York)"} · Yahoo Finance
        </p>
      )}
    </section>
  );
}
