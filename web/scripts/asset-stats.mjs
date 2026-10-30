// Market statistics for one asset, computed from Yahoo Finance's daily history, for asset pages:
// returns, annualized volatility, max drawdown, beta against its market's index, trailing dividends and liquidity.
// The asset-page skill copies these numbers as they are: the model never estimates them.
//
//   node scripts/asset-stats.mjs PETR4 br-stocks
//   node scripts/asset-stats.mjs SPY us-etfs
//   node scripts/asset-stats.mjs MXRF11 fiis
import { pathToFileURL } from "node:url";

const markets = {
  "br-stocks": { suffix: ".SA", benchmark: "^BVSP", benchmarkName: "Ibovespa" },
  fiis: { suffix: ".SA", benchmark: "^BVSP", benchmarkName: "Ibovespa" },
  "us-etfs": { suffix: "", benchmark: "^GSPC", benchmarkName: "S&P 500" },
};
async function history(symbol, range = "10y") {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=${range}&interval=1d&events=div,split`;
  const response = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
  if (!response.ok) throw new Error(`${symbol}: HTTP ${response.status}`);
  const result = (await response.json()).chart?.result?.[0];
  if (!result) throw new Error(`${symbol}: no data`);
  const quote = result.indicators.quote[0];
  const adjusted = result.indicators.adjclose?.[0]?.adjclose ?? quote.close;
  const days = result.timestamp
    .map((t, i) => ({ date: new Date(t * 1000).toISOString().slice(0, 10), close: quote.close[i], adj: adjusted[i], volume: quote.volume[i] }))
    .filter((d) => d.close && d.adj);
  const dividends = Object.values(result.events?.dividends ?? {}).map((d) => ({ date: new Date(d.date * 1000).toISOString().slice(0, 10), amount: d.amount }));
  return { meta: result.meta, days, dividends };
}

const round = (x, digits = 4) => (x == null || !Number.isFinite(x) ? null : Number(x.toFixed(digits)));
const dateYearsAgo = (end, years) => { const d = new Date(end); d.setFullYear(d.getFullYear() - years); return d.toISOString().slice(0, 10); };

/** Total return (adjusted closes, so dividends and splits are in) from the first session on or after `years` ago. */
function totalReturn(days, years) {
  const start = dateYearsAgo(days.at(-1).date, years);
  const first = days.find((d) => d.date >= start);
  // Not enough history: the first session must fall within ten days of the start.
  if (!first || (new Date(first.date) - new Date(start)) / 86_400_000 > 10) return null;
  return days.at(-1).adj / first.adj - 1;
}

function logReturns(days) {
  return days.slice(1).map((d, i) => ({ date: d.date, r: Math.log(d.adj / days[i].adj) }));
}

function stdev(values) {
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  return Math.sqrt(values.reduce((a, b) => a + (b - mean) ** 2, 0) / (values.length - 1));
}

function maxDrawdown(days) {
  let peak = -Infinity, worst = 0, worstAt = null, peakAt = null, worstPeakAt = null;
  for (const d of days) {
    if (d.adj > peak) { peak = d.adj; peakAt = d.date; }
    const drawdown = d.adj / peak - 1;
    if (drawdown < worst) { worst = drawdown; worstAt = d.date; worstPeakAt = peakAt; }
  }
  return { drawdown: round(worst), from: worstPeakAt, to: worstAt };
}

export async function assetStats(ticker, list) {
  const market = markets[list];
  if (!market) throw new Error(`unknown list ${list}`);
  const asset = await history(ticker + market.suffix);
  const index = await history(market.benchmark);
  const { days, dividends, meta } = asset;
  const last = days.at(-1);
  const oneYearAgo = dateYearsAgo(last.date, 1);
  const yearDays = days.filter((d) => d.date >= oneYearAgo);
  const yearReturns = logReturns(yearDays);

  // Beta over the last year, on days both traded.
  const indexByDate = new Map(logReturns(index.days.filter((d) => d.date >= oneYearAgo)).map((x) => [x.date, x.r]));
  const paired = yearReturns.filter((x) => indexByDate.has(x.date)).map((x) => [x.r, indexByDate.get(x.date)]);
  const meanA = paired.reduce((s, [a]) => s + a, 0) / paired.length, meanB = paired.reduce((s, [, b]) => s + b, 0) / paired.length;
  const covariance = paired.reduce((s, [a, b]) => s + (a - meanA) * (b - meanB), 0) / (paired.length - 1);
  const varianceB = paired.reduce((s, [, b]) => s + (b - meanB) ** 2, 0) / (paired.length - 1);

  const trailing = dividends.filter((d) => d.date >= oneYearAgo);
  const dividendsTTM = trailing.reduce((s, d) => s + d.amount, 0);
  const threeMonthsAgo = new Date(last.date); threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);
  const recent = days.filter((d) => d.date >= threeMonthsAgo.toISOString().slice(0, 10) && d.volume);
  const volatility = stdev(yearReturns.map((x) => x.r)) * Math.sqrt(252);

  return {
    ticker,
    list,
    asOf: last.date,
    source: "Yahoo Finance daily history (adjusted closes include dividends and splits)",
    name: meta.longName ?? meta.shortName ?? null,
    currency: meta.currency,
    price: round(last.close, 2),
    historyStarts: days[0].date,
    returns: { "1y": round(totalReturn(days, 1)), "3y": round(totalReturn(days, 3)), "5y": round(totalReturn(days, 5)), "10y": round(totalReturn(days, 10)) },
    volatility1y: round(volatility),
    volatilityLevel: volatility < 0.15 ? "baixa" : volatility < 0.25 ? "moderada" : volatility < 0.4 ? "alta" : "muito alta",
    maxDrawdown5y: maxDrawdown(days.filter((d) => d.date >= dateYearsAgo(last.date, 5))),
    beta1y: { value: round(covariance / varianceB, 2), against: market.benchmarkName },
    dividends: dividends.length
      ? { last12Months: round(dividendsTTM, 4), payments12Months: trailing.length, yield12Months: round(dividendsTTM / last.close), lastPayment: dividends.at(-1) }
      : null,
    avgDailyTradedValue3m: recent.length ? Math.round(recent.reduce((s, d) => s + d.close * d.volume, 0) / recent.length) : null,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [ticker, list] = process.argv.slice(2);
  if (!ticker || !markets[list]) {
    console.error("usage: node scripts/asset-stats.mjs <TICKER> <br-stocks|us-etfs|fiis>");
    process.exit(1);
  }
  console.log(JSON.stringify(await assetStats(ticker, list), null, 2));
}
