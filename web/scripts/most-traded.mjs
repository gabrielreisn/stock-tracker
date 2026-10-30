// Ranks candidate tickers by average daily traded value (close × volume) over the last 3 months, from Yahoo
// Finance's daily bars, and writes the top 100 of each list to src/data/assets/<list>.json.
// Tickers Yahoo doesn't know (delisted, renamed) drop out on their own.
//
//   node scripts/most-traded.mjs            all lists
//   node scripts/most-traded.mjs fiis       one list
//
// The candidates are a generous pool, not the answer: anything liquid enough to make the top 100 should be in it.
// Each pool joins a fixed list with a live one: the members of B3's IBrA (Índice Brasil Amplo: the most traded stocks,
// one share class each) and IFIX (the most traded FIIs), every FII the CVM lists as traded on B3, and the 500 ETFs Yahoo
// lists as most active by shares traded.
// The fixed lists add what those miss: other share classes (PETR3) and high-priced ETFs that trade fewer shares (VOO).
import { execFileSync } from "node:child_process";
import { mkdir, stat, writeFile } from "node:fs/promises";

const top = 100;

const lists = {
  "br-stocks": {
    title: "Ações brasileiras mais negociadas",
    suffix: ".SA",
    currency: "BRL",
    exchange: "B3",
    candidates: `PETR4 PETR3 VALE3 ITUB4 ITUB3 BBDC4 BBDC3 BBAS3 B3SA3 ABEV3 WEGE3 ITSA4 ELET3 ELET6 AXIA3 AXIA6 RENT3 SUZB3
      PRIO3 BPAC11 RADL3 EQTL3 LREN3 GGBR4 MGLU3 RAIL3 VBBR3 HAPV3 CSAN3 BBSE3 CMIG4 SBSP3 UGPA3 EMBR3 EMBJ3 TOTS3 RDOR3
      VIVT3 KLBN11 CPLE6 CPLE3 CSNA3 USIM5 BRFS3 MBRF3 NTCO3 NATU3 CCRO3 MOTV3 ASAI3 CRFB3 COGN3 YDUQ3 AZZA3 SANB11 BRAP4
      GOAU4 CYRE3 MRVE3 EZTC3 ENEV3 EGIE3 TAEE11 CPFE3 NEOE3 HYPE3 FLRY3 MULT3 IGTI11 ALOS3 SMFT3 CXSE3 PSSA3 IRBR3 CMIN3
      RECV3 BRKM5 STBP3 POMO4 VAMO3 SLCE3 SMTO3 AURE3 ISAE4 TRPL4 BEEF3 JBSS3 MRFG3 GMAT3 VIVA3 AZUL4 GOLL4 CVCB3 RAIZ4
      DIRR3 CURY3 TIMS3 INTB3 POSI3 LWSA3 CASH3 BHIA3 PCAR3 CEAB3 ANIM3 RAPT4 ECOR3 SAPR11 CSMG3 ALPA4 KEPL3 TUPY3 MOVI3`,
  },
  "us-etfs": {
    title: "ETFs americanos mais negociados",
    suffix: "",
    currency: "USD",
    exchange: "NYSE Arca / Nasdaq",
    candidates: `SPY QQQ IVV VOO IWM VTI TQQQ SQQQ HYG LQD TLT IEF SHY GLD SLV EEM EFA IEFA IEMG XLF XLE XLK XLV XLI XLY XLP
      XLU XLB XLRE XLC SMH SOXX SOXL SOXS KRE XBI GDX GDXJ ARKK IBIT FBTC ETHA UVXY VXX SPXL SPXS UPRO SH BND AGG BIL SGOV
      VEA VWO VGT SCHD JEPI JEPQ DIA MDY RSP USO UNG FXI KWEB EWZ EWJ INDA TSLL NVDL TZA TNA LABU BITO MSTU SPLG QQQM VUG
      VTV IWF IWD IJR VB TSLZ NVDX MSTX ETHE GBTC IJH VO VXUS VCIT VCSH MUB TIP VNQ IAU SCHX SCHB SCHG ITOT SPYG SPYV
      MTUM QUAL USMV IWB IWV IVW IVE OEF VIG VYM DGRO XLG RSPT SPMO SMH COWZ AVUV DFAC BSV BIV BLV VGIT VGSH VGLT GOVT
      MBB EMB BKLN SRLN JNK USHY SPSB SPIB IGIB IGSB FLOT USFR TFLO SHV SPTL SPTS SCHO SCHR`,
  },
  fiis: {
    title: "FIIs mais negociados",
    suffix: ".SA",
    currency: "BRL",
    exchange: "B3",
    // Fundos imobiliários only: Fiagros (SNAG11, RURA11, KNCA11…) and FI-Infra are other fund types.
    candidates: `MXRF11 HGLG11 KNRI11 XPML11 VISC11 BTLG11 KNCR11 HGRU11 CPTS11 IRDM11 VGIR11 TRXF11 PVBI11 HSML11 KNIP11
      BCFF11 RECR11 GARE11 VILG11 ALZR11 HGRE11 JSRE11 BRCO11 XPLG11 TGAR11 MCCI11 KNSC11 RBRR11 HCTR11 DEVA11 VGHF11
      KNHF11 PMLL11 MALL11 HFOF11 BCRI11 RZTR11 RZAK11 VRTA11 CVBI11 GGRC11 LVBI11 XPCI11 BTCI11 KNUQ11 CLIN11 RBRF11
      RBRY11 HGCR11 KFOF11 VGRI11 TVRI11 PCIP11 RBVA11 GTWR11 BRCR11 HGBS11 VINO11 MCRE11 XPIN11 VSLH11 BPML11 RBRL11
      SARE11 HABT11 URPR11 OUJP11 CPSH11 TRXB11 KISU11 BTAL11 BCIA11 HCRI11 RBRP11 HGPO11 PATL11 SADI11 BLMG11`,
  },
};

const DAY = 86_400;

/** Members of a B3 index today (IBRA, IFIX…), from B3's own index pages. */
async function b3Index(index) {
  const query = Buffer.from(JSON.stringify({ language: "pt-br", pageNumber: 1, pageSize: 500, index, segment: "1" })).toString("base64");
  const response = await fetch(`https://sistemaswebb3-listados.b3.com.br/indexProxy/indexCall/GetPortfolioDay/${query}`);
  if (!response.ok) throw new Error(`B3 ${index}: HTTP ${response.status}`);
  return (await response.json()).results.map((r) => r.cod.trim());
}

/** The ETFs Yahoo Finance lists as most active today, by shares traded (250 a page). */
async function yahooMostActiveETFs(count = 500) {
  const symbols = [];
  for (let start = 0; start < count; start += 250) {
    const url = `https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved?scrIds=most_actives_etfs&count=250&start=${start}`;
    const response = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!response.ok) throw new Error(`Yahoo screener: HTTP ${response.status}`);
    symbols.push(...(await response.json()).finance.result[0].quotes.filter((q) => q.quoteType === "ETF").map((q) => q.symbol));
  }
  return symbols;
}

/**
 * Every FII the CVM's monthly reports list as traded on B3, as tickers: an ISIN like BRMXRFCTF… is MXRF11. Funds with
 * newer codes unrelated to the ticker (BR0EBICTF…) can't be mapped; the IFIX brings in the liquid ones among them.
 * The dataset is shared with scripts/asset-sources.mjs through .cache/datasets/.
 */
async function cvmListedFIIs() {
  for (const year of [new Date().getFullYear(), new Date().getFullYear() - 1]) {
    const name = `inf_mensal_fii_${year}`;
    const zip = new URL(`../.cache/datasets/${name}.zip`, import.meta.url);
    if (!(await stat(zip).catch(() => null))) {
      const response = await fetch(`https://dados.cvm.gov.br/dados/FII/DOC/INF_MENSAL/DADOS/${name}.zip`);
      if (!response.ok) continue;
      await mkdir(new URL(".", zip), { recursive: true });
      await writeFile(zip, Buffer.from(await response.arrayBuffer()));
    }
    const [header, ...rows] = execFileSync("unzip", ["-p", zip.pathname, `inf_mensal_fii_geral_${year}.csv`], { maxBuffer: 1 << 28 })
      .toString("latin1").split(/\r?\n/);
    const columns = header.split(";");
    const isin = columns.indexOf("Codigo_ISIN"), onExchange = columns.indexOf("Mercado_Negociacao_Bolsa");
    const tickers = new Set();
    for (const row of rows) {
      const cells = row.split(";");
      const root = cells[onExchange] === "S" && /^BR([A-Z]{4})CTF/.exec(cells[isin] ?? "")?.[1];
      if (root) tickers.add(`${root}11`);
    }
    return [...tickers];
  }
  return [];
}

const livePools = {
  "br-stocks": () => b3Index("IBRA"),
  fiis: async () => [...await b3Index("IFIX"), ...await cvmListedFIIs()],
  "us-etfs": () => yahooMostActiveETFs(),
};

async function bars(symbol) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=3mo&interval=1d`;
  const response = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
  if (!response.ok) return null;
  const result = (await response.json()).chart?.result?.[0];
  const quote = result?.indicators?.quote?.[0];
  if (!result || !quote) return null;
  const values = result.timestamp.map((_, i) => (quote.close[i] ?? 0) * (quote.volume[i] ?? 0)).filter((v) => v > 0);
  // Fewer than ~40 sessions in 3 months: newly listed or barely traded.
  if (values.length < 40) return null;
  const lastTrade = result.meta.regularMarketTime ?? result.timestamp.at(-1);
  if (Date.now() / 1000 - lastTrade > 10 * DAY) return null; // stopped trading
  return {
    name: result.meta.longName ?? result.meta.shortName ?? null,
    avgDailyValue: Math.round(values.reduce((a, b) => a + b, 0) / values.length),
    lastPrice: result.meta.regularMarketPrice ?? null,
  };
}

/** Runs `task` over `items` a few at a time, so Yahoo doesn't throttle us. */
async function pool(items, size, task) {
  const results = [];
  let next = 0;
  await Promise.all(Array.from({ length: size }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await task(items[i]).catch(() => null);
    }
  }));
  return results;
}

async function rank(key) {
  const list = lists[key];
  const live = await livePools[key]().catch((error) => {
    console.warn(`${key}: ${error.message}; ranking the fixed candidates only`);
    return [];
  });
  const tickers = [...new Set([...list.candidates.split(/\s+/), ...live].filter(Boolean))];
  const data = await pool(tickers, 6, (ticker) => bars(ticker + list.suffix));
  const ranked = tickers
    .map((ticker, i) => data[i] && { ticker, ...data[i] })
    .filter(Boolean)
    .sort((a, b) => b.avgDailyValue - a.avgDailyValue)
    .slice(0, top)
    .map((asset, i) => ({
      rank: i + 1,
      ticker: asset.ticker,
      slug: asset.ticker.toLowerCase(),
      name: asset.name,
      exchange: list.exchange,
      currency: list.currency,
      avgDailyValue: asset.avgDailyValue,
      lastPrice: asset.lastPrice,
    }));
  const file = {
    list: key,
    title: list.title,
    measure: "Average daily traded value (close × volume) over the last 3 months",
    currency: list.currency,
    source: "Yahoo Finance daily bars",
    generatedAt: new Date().toISOString().slice(0, 10),
    candidates: tickers.length,
    found: data.filter(Boolean).length,
    assets: ranked,
  };
  await mkdir(new URL("../src/data/assets/", import.meta.url), { recursive: true });
  await writeFile(new URL(`../src/data/assets/${key}.json`, import.meta.url), JSON.stringify(file, null, 2) + "\n");
  console.log(`${key}: ${file.found}/${tickers.length} candidates found, top ${ranked.length} written`);
}

for (const key of process.argv[2] ? [process.argv[2]] : Object.keys(lists)) await rank(key);
