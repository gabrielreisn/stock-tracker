// Public information about one asset, gathered from primary sources so pages are written from documents instead of
// a model's memory. Every source keeps its URL and the date it was read, so the page can cite it.
//   Brazilian stocks  B3 (listed company record), CVM (company registry and material facts), Wikidata, Wikipedia
//   FIIs              CVM (monthly report), FNET (offerings, material facts and the latest management report)
//   US ETFs           Wikipedia and Wikidata
// The result is a dossier: sources (facts, dated events, text excerpts), the characteristics table and profile built
// from them, and the computed stats. Public datasets are cached in .cache/ for a few days.
//
//   node scripts/asset-sources.mjs PETR4
import { execFileSync } from "node:child_process";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { extractText, getDocumentProxy } from "unpdf";
import { assetStats } from "./asset-stats.mjs";
import { bigMoney, date, integer, isoDate, money, percent, sentenceCase, titleCase } from "./pt-br.mjs";

export const root = new URL("../", import.meta.url);
const readJSON = async (path) => JSON.parse(await readFile(new URL(path, root), "utf8"));
export const catalog = await readJSON("src/data/app-features.json");
export const lists = Object.fromEntries(await Promise.all(
  ["br-stocks", "us-etfs", "fiis"].map(async (l) => [l, (await readJSON(`src/data/assets/${l}.json`)).assets]),
));

/** The listed asset for a ticker, with its list and page path, or null. */
export function findAsset(ticker) {
  for (const [list, assets] of Object.entries(lists)) {
    const asset = assets.find((a) => a.ticker === ticker.toUpperCase());
    if (asset) return { ...asset, list, path: catalog.site.assetPaths[list].replace("{slug}", asset.slug) };
  }
  return null;
}

const today = new Date().toISOString().slice(0, 10);
const thisYear = new Date().getFullYear();
const userAgent = "StockBar-web/0.1 (asset page research)";
const browser = { "User-Agent": "Mozilla/5.0" };

// Wikimedia rate-limits clients that ask too fast (HTTP 429): space requests to its sites, and wait and retry when
// it asks to.
const politeHosts = /(^|\.)(wikipedia|wikidata)\.org$/;
let lastPolite = 0;
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function get(url, { json = true, headers = {} } = {}) {
  const polite = politeHosts.test(new URL(url).hostname);
  for (let attempt = 0; ; attempt++) {
    if (polite) {
      const wait = lastPolite + 250 - Date.now();
      if (wait > 0) await sleep(wait);
      lastPolite = Date.now();
    }
    const response = await fetch(url, { headers: { "User-Agent": userAgent, ...headers } });
    if (response.status === 429 && attempt < 3) {
      await sleep((Number(response.headers.get("retry-after")) || 5 * (attempt + 1)) * 1000);
      continue;
    }
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    return json ? response.json() : Buffer.from(await response.arrayBuffer());
  }
}

/** A public dataset file, downloaded at most once every few days. Returns its local path. */
async function cached(url, name, days = 3) {
  const file = new URL(`.cache/datasets/${name}`, root);
  const age = await stat(file).then((s) => Date.now() - s.mtimeMs, () => Infinity);
  if (age > days * 86_400_000) {
    const data = await get(url, { json: false });
    await mkdir(new URL(".", file), { recursive: true });
    await writeFile(file, data);
  }
  return file.pathname;
}

const parsed = new Map();
/** Rows of a CVM CSV (semicolon-separated, Latin-1), straight or from inside a zip. Parsed once per run. */
async function cvmCSV(url, name, member) {
  const key = `${name}/${member ?? ""}`;
  if (!parsed.has(key)) {
    const path = await cached(url, name);
    const data = member ? execFileSync("unzip", ["-p", path, member], { maxBuffer: 1 << 28 }) : await readFile(path);
    const [header, ...lines] = new TextDecoder("latin1").decode(data).split(/\r?\n/).filter(Boolean);
    const keys = header.split(";");
    parsed.set(key, lines.map((line) => Object.fromEntries(line.split(";").map((v, i) => [keys[i], v]))));
  }
  return parsed.get(key);
}

/** Cuts text at a paragraph or sentence boundary before `limit` characters. */
function clip(text, limit) {
  if (text.length <= limit) return text;
  const cut = text.slice(0, limit);
  const at = Math.max(cut.lastIndexOf("\n\n"), cut.lastIndexOf(". ") + 1);
  return (at > limit * 0.6 ? cut.slice(0, at) : cut).trim() + " […]";
}

const source = (title, url, { facts = [], events = [], text = "" } = {}) =>
  ({ title, url, accessedAt: today, facts: facts.filter((f) => f.value), events: events.filter((e) => e.date), text });

const formatCNPJ = (cnpj) => cnpj.replace(/\D/g, "").padStart(14, "0").replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
const https = (site) => (!site ? null : /^https?:\/\//.test(site) ? site.replace(/^http:/, "https:") : `https://${site.trim()}`);

// MARK: - B3

const b3 = "https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall";
const base64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64");
// B3 writes commas as ". " in its text fields.
const b3Text = (s) => s?.replace(/\. (?=\S)/g, ", ").replace(/\.$/, "");
const listingSegments = { "NOVO MERCADO": "Novo Mercado", "NIVEL 1": "Nível 1", "NIVEL 2": "Nível 2", "BOVESPA MAIS": "Bovespa Mais" };

async function b3Company(ticker) {
  const issuer = ticker.slice(0, 4);
  const { results } = await get(`${b3}/GetInitialCompanies/${base64({ language: "pt-br", pageNumber: 1, pageSize: 20, company: issuer })}`);
  const match = results.find((r) => r.issuingCompany === issuer);
  if (!match) return null;
  const d = await get(`${b3}/GetDetail/${base64({ codeCVM: match.codeCVM, language: "pt-br" })}`);
  const classification = b3Text(d.industryClassification);
  const [sector, , segment] = classification?.split(" / ") ?? [];
  const listing = Object.entries(listingSegments).find(([k]) => d.market?.includes(k))?.[1] ?? d.market;
  const codes = d.otherCodes.map((c) => c.code).filter((c) => /^[A-Z]{4}\d{1,2}$/.test(c));
  const quotedSince = isoDate(d.dateQuotation);
  return {
    detail: d, sector, segment, listing, codes, quotedSince,
    source: source(`B3: ${d.tradingName}, dados da companhia listada`,
      `https://sistemaswebb3-listados.b3.com.br/listedCompaniesPage/main/${d.codeCVM}/${issuer}/overview?language=pt-br`, {
        facts: [
          { label: "Nome de pregão", value: d.tradingName },
          { label: "Classificação setorial (B3)", value: classification },
          { label: "Atividade", value: b3Text(d.activity) },
          { label: "Segmento de listagem", value: listing },
          { label: "Códigos de negociação", value: codes.join(", ") },
          { label: "Início da cotação na B3", value: date(quotedSince) },
          { label: "Site", value: d.website },
        ],
        events: [{ date: quotedSince, event: "Início da cotação das ações na bolsa" }],
      }),
  };
}

// MARK: - CVM: public companies

async function cvmCompany(cnpj) {
  const rows = await cvmCSV("https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv", "cad_cia_aberta.csv");
  const r = rows.find((x) => x.CNPJ_CIA === cnpj && x.TP_MERC === "BOLSA") ?? rows.find((x) => x.CNPJ_CIA === cnpj);
  if (!r) return null;
  const headquarters = r.MUN && `${titleCase(r.MUN)} (${r.UF})`;
  return {
    row: r, headquarters,
    source: source(`CVM: cadastro de companhia aberta, ${r.DENOM_SOCIAL}`, "https://dados.cvm.gov.br/dataset/cia_aberta-cad", {
      facts: [
        { label: "Denominação social", value: r.DENOM_SOCIAL },
        { label: "CNPJ", value: r.CNPJ_CIA },
        { label: "Data de constituição", value: date(r.DT_CONST) },
        { label: "Registro de companhia aberta na CVM", value: date(r.DT_REG) },
        { label: "Setor de atividade (CVM)", value: r.SETOR_ATIV },
        { label: "Controle acionário", value: sentenceCase(r.CONTROLE_ACIONARIO) },
        { label: "Sede", value: headquarters },
        { label: "Auditor independente", value: r.AUDITOR },
        { label: "Diretor de relações com investidores", value: /RELAÇÕES COM INVESTIDORES/.test(r.TP_RESP) ? r.RESP : null },
      ],
      events: [
        { date: r.DT_CONST, event: "Constituição da companhia" },
        { date: r.DT_REG, event: "Registro como companhia aberta na CVM" },
      ],
    }),
  };
}

/** The company's latest material facts (fatos relevantes) filed with the CVM, one source each. */
async function cvmMaterialFacts(cnpj, { months = 24, max = 8 } = {}) {
  const rows = [];
  for (const y of [thisYear - 1, thisYear]) {
    const name = `ipe_cia_aberta_${y}`;
    rows.push(...await cvmCSV(`https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/${name}.zip`, `${name}.zip`, `${name}.csv`).catch(() => []));
  }
  const since = new Date(Date.now() - months * 30.4 * 86_400_000).toISOString().slice(0, 10);
  const latest = new Map(); // a later version of the same filing replaces the earlier one
  for (const r of rows) {
    if (r.CNPJ_Companhia === cnpj && r.Categoria === "Fato Relevante" && r.Assunto && r.Data_Referencia >= since) latest.set(`${r.Data_Referencia} ${r.Assunto}`, r);
  }
  return [...latest.values()]
    .sort((a, b) => b.Data_Referencia.localeCompare(a.Data_Referencia))
    .slice(0, max)
    .map((r) => source(`CVM: fato relevante de ${date(r.Data_Referencia)}, “${r.Assunto.trim()}”`, r.Link_Download, {
      events: [{ date: r.Data_Referencia, event: r.Assunto.trim() }],
    }));
}

// MARK: - CVM and FNET: real estate funds (FIIs)

// Words that every fund name has, left out when matching names.
const fundWords = new Set(["fundo", "de", "do", "da", "investimento", "investimentos", "imobiliario", "imobiliarios", "fii", "responsabilidade", "limitada", "rl", "-"]);
const nameWords = (s) => plain(s).split(/[^a-z0-9]+/).filter((w) => w && !fundWords.has(w));

/**
 * The fund's latest CVM monthly report. Found by its ISIN, which usually starts with the ticker (BRMXRFCTF…), or else
 * by name: renamed funds keep their old code (PMLL11 is BRMALLCTF…) and newer ones get codes unrelated to the ticker
 * (KNUQ11 is BR0EBICTF…).
 */
async function cvmFund(ticker, listedName) {
  const isin = `BR${ticker.slice(0, 4)}CTF`;
  const wanted = nameWords(listedName ?? "");
  const sameName = (r) => {
    const words = new Set(nameWords(r.Nome_Fundo_Classe ?? ""));
    return wanted.length >= 2 && wanted.every((w) => words.has(w));
  };
  for (const y of [thisYear, thisYear - 1]) {
    const name = `inf_mensal_fii_${y}`;
    const url = `https://dados.cvm.gov.br/dados/FII/DOC/INF_MENSAL/DADOS/${name}.zip`;
    const general = await cvmCSV(url, `${name}.zip`, `inf_mensal_fii_geral_${y}.csv`).catch(() => []);
    let rows = general.filter((r) => r.Codigo_ISIN?.startsWith(isin));
    if (!rows.length) {
      // Only when the name points to a single fund.
      const byName = general.filter(sameName);
      if (new Set(byName.map((r) => r.CNPJ_Fundo_Classe)).size === 1) rows = byName;
    }
    if (!rows.length) continue;
    const newest = (a, b) => (b.Data_Referencia > a.Data_Referencia || (b.Data_Referencia === a.Data_Referencia && +b.Versao > +a.Versao) ? b : a);
    const g = rows.reduce(newest);
    const c = (await cvmCSV(url, `${name}.zip`, `inf_mensal_fii_complemento_${y}.csv`))
      .filter((r) => r.CNPJ_Fundo_Classe === g.CNPJ_Fundo_Classe && r.Data_Referencia === g.Data_Referencia)
      .reduce(newest, { Data_Referencia: "" });
    const month = date(g.Data_Referencia.slice(0, 7));
    const number = (s) => (s ? Number(s) : null);
    return {
      general: g, month,
      netAssets: number(c.Patrimonio_Liquido), shareholders: number(c.Total_Numero_Cotistas), bookValue: number(c.Valor_Patrimonial_Cotas),
      source: source(`CVM: informe mensal do ${g.Nome_Fundo_Classe} (${month})`, "https://dados.cvm.gov.br/dataset/fii-doc-inf_mensal", {
        facts: [
          { label: "Nome", value: g.Nome_Fundo_Classe },
          { label: "CNPJ", value: g.CNPJ_Fundo_Classe },
          { label: "Início das atividades", value: date(g.Data_Funcionamento) },
          { label: "Público-alvo", value: sentenceCase(g.Publico_Alvo) },
          { label: "Mandato", value: g.Mandato },
          { label: "Segmento de atuação", value: g.Segmento_Atuacao },
          { label: "Tipo de gestão", value: g.Tipo_Gestao },
          { label: "Prazo de duração", value: g.Prazo_Duracao },
          { label: "Administrador", value: g.Nome_Administrador },
          { label: `Patrimônio líquido (${month})`, value: bigMoney(number(c.Patrimonio_Liquido)) },
          { label: `Número de cotistas (${month})`, value: c.Total_Numero_Cotistas && integer(number(c.Total_Numero_Cotistas)) },
          { label: `Valor patrimonial da cota (${month})`, value: money(number(c.Valor_Patrimonial_Cotas)) },
          { label: `Cotas emitidas (${month})`, value: c.Cotas_Emitidas && integer(number(c.Cotas_Emitidas)) },
          { label: `Taxa de administração no mês (${month}), sobre o patrimônio`, value: percent(number(c.Percentual_Despesas_Taxa_Administracao), 3) },
          { label: `Dividend yield do mês (${month}), informado pelo fundo`, value: percent(number(c.Percentual_Dividend_Yield_Mes)) },
        ],
        events: [{ date: g.Data_Funcionamento, event: "Início das atividades do fundo" }],
      }),
    };
  }
  return null;
}

const fnet = "https://fnet.bmfbovespa.com.br/fnet/publico";

async function fnetDocuments(cnpj) {
  const documents = [];
  for (let start = 0; start < 1000; start += 200) {
    const page = await get(`${fnet}/pesquisarGerenciadorDocumentosDados?d=0&s=${start}&l=200&o%5B0%5D%5BdataEntrega%5D=desc&cnpjFundo=${cnpj}`,
      { headers: { ...browser, "X-Requested-With": "XMLHttpRequest" } });
    documents.push(...page.data);
    if (page.data.length < 200) break;
  }
  return documents;
}

async function fnetText(id, limit, { skipPreamble = false } = {}) {
  const data = await get(`${fnet}/downloadDocumento?id=${id}`, { json: false, headers: browser });
  let text;
  if (data.subarray(0, 4).toString() === "%PDF") {
    text = (await extractText(await getDocumentProxy(new Uint8Array(data), { verbosity: 0 }), { mergePages: true })).text;
  } else {
    text = data.toString("utf8").replace(/<[^>]+>/g, " ");
  }
  text = text.replace(/[ \t\u00a0]+/g, " ").replace(/\s*\n\s*/g, "\n").trim();
  // Material facts open with the administrator's legal identification; the news starts at "comunica(m) aos cotistas".
  const start = skipPreamble ? text.search(/\b(vem|vêm)?[^.]{0,40}?\b(comunica|informa)\w*,?\s+(aos\s+(seus\s+)?cotistas|ao\s+mercado)/i) : -1;
  return clip(start > 0 ? text.slice(start) : text, limit);
}

/** Offerings and filings from FNET, the latest management report and material facts as text. */
async function fnetSources(cnpj, fundName) {
  const documents = await fnetDocuments(cnpj);
  const registeredName = documents[0]?.descricaoFundo?.replace(/\s+-\s+RESPONSABILIDADE LIMITADA$|\s+RESP(ONSABILIDADE)? LTDA$/i, "");
  const type = (d) => (d.tipoDocumento ?? "").trim();
  const when = (d) => isoDate(d.dataReferencia) ?? isoDate(d.dataEntrega);
  const offerings = documents.filter((d) => ["Anúncio de Início", "Anúncio de Encerramento"].includes(type(d)));
  const oldest = documents.map((d) => isoDate(d.dataEntrega)).filter(Boolean).sort()[0];
  const sources = [source(`FNET (B3): documentos publicados pelo ${fundName}`, `${fnet}/abrirGerenciadorDocumentosCVM?cnpjFundo=${cnpj}`, {
    facts: [
      { label: "Documentos publicados no FNET", value: documents.length && `${integer(documents.length)}${documents.length >= 1000 ? " ou mais" : ""}, desde ${date(oldest)}` },
      { label: "Ofertas públicas de cotas encerradas", value: String(offerings.filter((d) => type(d) === "Anúncio de Encerramento").length) },
    ],
    events: offerings.map((d) => ({
      date: when(d),
      event: type(d) === "Anúncio de Início" ? "Início de oferta pública de cotas (nova emissão)" : "Encerramento de oferta pública de cotas (nova emissão)",
    })),
  })];

  const report = documents.find((d) => type(d) === "Relatório Gerencial");
  if (report) {
    sources.push(source(`Relatório gerencial do ${fundName}, referência ${report.dataReferencia}`, `${fnet}/exibirDocumento?id=${report.id}`,
      { text: await fnetText(report.id, 7000).catch(() => "") }));
  }
  const since = new Date(Date.now() - 18 * 30.4 * 86_400_000).toISOString().slice(0, 10);
  for (const fact of documents.filter((d) => d.categoriaDocumento === "Fato Relevante" && when(d) >= since).slice(0, 2)) {
    sources.push(source(`Fato relevante do ${fundName}, ${date(when(fact))}`, `${fnet}/exibirDocumento?id=${fact.id}`,
      { text: await fnetText(fact.id, 1800, { skipPreamble: true }).catch(() => "") }));
  }
  return { registeredName, sources: sources.filter((s) => s.text || s.facts.length || s.events.length) };
}

// MARK: - Wikidata and Wikipedia

async function sparql(query) {
  const url = `https://query.wikidata.org/sparql?query=${encodeURIComponent(query)}`;
  return (await get(url, { headers: { Accept: "application/sparql-results+json" } })).results.bindings;
}

/** The company's Wikidata item, by CNPJ or by a ticker it lists on an exchange. */
async function wikidataIdForCompany(cnpj, tickers) {
  const digits = cnpj.replace(/\D/g, "");
  const values = (xs) => xs.map((x) => `"${x}"`).join(" ");
  const rows = await sparql(`SELECT ?item WHERE {
    { VALUES ?cnpj { ${values([cnpj, digits])} } ?item wdt:P6204 ?cnpj . }
    UNION { VALUES ?ticker { ${values(tickers)} } ?item p:P414 ?listing . ?listing pq:P249 ?ticker . }
  } LIMIT 1`);
  return rows[0]?.item.value.split("/").at(-1) ?? null;
}

async function wikidataIdByArticle(lang, title) {
  const j = await get(`https://www.wikidata.org/w/api.php?action=wbgetentities&sites=${lang}wiki&titles=${encodeURIComponent(title)}&props=info&format=json`);
  return Object.keys(j.entities ?? {}).find((id) => id.startsWith("Q")) ?? null;
}

const wikidataTime = ({ time, precision }) => {
  const [y, m, d] = time.slice(1, 11).split("-");
  return precision >= 11 ? `${y}-${m}-${d}` : precision === 10 ? `${y}-${m}` : y;
};

async function wikidata(id) {
  const entity = (await get(`https://www.wikidata.org/wiki/Special:EntityData/${id}.json`)).entities[id];
  const claims = (p) => (entity.claims[p] ?? []).filter((c) => c.rank !== "deprecated" && c.mainsnak.datavalue);
  // Current values only: a claim with an end time (P582) is history.
  const current = (p) => claims(p).filter((c) => !c.qualifiers?.P582);
  const items = (p) => current(p).map((c) => c.mainsnak.datavalue.value.id);
  const wanted = { P159: "Sede", P112: "Fundadores", P169: "Presidente (CEO)", P127: "Controladores ou proprietários", P749: "Empresa controladora" };
  const ids = [...new Set(Object.keys(wanted).flatMap(items))].slice(0, 50);
  const labels = ids.length
    ? (await get(`https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${ids.join("|")}&props=labels&languages=pt|en&format=json`)).entities
    : {};
  const label = (q) => labels[q]?.labels?.pt?.value ?? labels[q]?.labels?.en?.value;
  const inception = claims("P571")[0]?.mainsnak.datavalue.value;
  const employees = current("P1128").at(-1);
  const name = entity.labels.pt?.value ?? entity.labels.en?.value;
  return {
    name,
    articles: { pt: entity.sitelinks.ptwiki?.title, en: entity.sitelinks.enwiki?.title },
    inception: inception && wikidataTime(inception),
    source: source(`Wikidata: ${name}`, `https://www.wikidata.org/wiki/${id}`, {
      facts: [
        { label: "Fundação", value: inception && date(wikidataTime(inception)) },
        ...Object.entries(wanted).map(([p, l]) => ({ label: l, value: items(p).map(label).filter(Boolean).join(", ") })),
        employees && {
          label: `Funcionários${employees.qualifiers?.P585 ? ` (${date(wikidataTime(employees.qualifiers.P585[0].datavalue.value))})` : ""}`,
          value: integer(Number(employees.mainsnak.datavalue.value.amount)),
        },
      ].filter(Boolean),
      events: [{ date: inception && inception.precision >= 9 ? wikidataTime(inception) : null, event: "Fundação" }],
    }),
  };
}

const notHistory = /^(ver também|referências|ligações externas|notas|bibliografia|leitura adicional|see also|references|external links|notes|further reading|bibliography)$/i;
const historyHeading = /hist|origem|origens|funda|privatiza|cronologia|evolu|background|formation|timeline|launch|development/i;

/**
 * The article's lead, then its history sections and the rest, as plain text within a budget. `prefer` (a regular
 * expression on headings) puts the sections that matter for this page first.
 */
async function wikipedia(lang, title, { lead = 2500, body = 7000, prefer } = {}) {
  const j = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&redirects=1&format=json&titles=${encodeURIComponent(title)}`);
  const page = Object.values(j.query.pages)[0];
  if (!page?.extract) return null;
  const parts = page.extract.split(/\n(={2,})\s*(.+?)\s*\1\n/);
  const sections = [];
  for (let i = 1; i < parts.length; i += 3) sections.push({ level: parts[i].length, heading: parts[i + 1], text: parts[i + 2].trim() });
  let inHistory = false, skipped = false;
  for (const s of sections) {
    if (s.level === 2) [inHistory, skipped] = [historyHeading.test(s.heading), notHistory.test(s.heading)];
    Object.assign(s, { inHistory, skipped });
  }
  const preferred = prefer ? sections.filter((s) => new RegExp(prefer, "i").test(s.heading)) : [];
  const chosen = [...new Set([...preferred, ...sections.filter((s) => s.inHistory), ...sections.filter((s) => !s.inHistory && !s.skipped)])].filter((s) => s.text);
  const text = [clip(parts[0].trim(), lead), clip(chosen.map((s) => `## ${s.heading}\n${s.text}`).join("\n\n"), body)].filter(Boolean).join("\n\n");
  const url = `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(page.title.replaceAll(" ", "_"))}`;
  return { title: page.title, text, source: source(`Wikipedia (${lang}): ${page.title}`, url, { text }) };
}

async function searchWikipedia(lang, query) {
  const j = await get(`https://${lang}.wikipedia.org/w/api.php?action=query&list=search&srlimit=3&format=json&srsearch=${encodeURIComponent(query)}`);
  return j.query.search.map((r) => r.title);
}

const plain = (s) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
const generic = new Set(["banco", "sa", "s.a.", "s/a", "cia", "companhia", "holding", "participacoes", "de", "do", "da", "e", "-", "brasil", "brasileiro", "brasileira"]);

/** A Wikipedia article for a company that Wikidata couldn't match by CNPJ: the top search result sharing a name word. */
async function findCompanyArticle(names) {
  for (const name of names.filter(Boolean)) {
    const words = plain(name).split(/[\s.,]+/).filter((w) => w.length > 2 && !generic.has(w));
    for (const title of await searchWikipedia("pt", name)) {
      if (words.some((w) => plain(title).includes(w))) return title;
    }
  }
  return null;
}

/**
 * The English article for an ETF that isn't in src/data/assets/etf-sources.json: a search result whose title shares a
 * word with the fund's name (not a "List of…") and whose text mentions the ticker. Only those are fetched.
 */
async function findETFArticle(ticker, names) {
  const words = new Set(names.filter(Boolean).flatMap((n) => plain(n).split(/[^a-z0-9&]+/)).filter((w) => w.length > 2 && !["etf", "trust", "fund", "the", "shares"].includes(w)));
  for (const query of names.filter(Boolean)) {
    for (const title of await searchWikipedia("en", query)) {
      if (/^list of/i.test(title) || !plain(title).split(/[^a-z0-9&]+/).some((w) => words.has(w))) continue;
      const article = await wikipedia("en", title, { lead: 4000, body: 8000 });
      if (article && new RegExp(`\\b${ticker}\\b`).test(article.text)) return article;
    }
  }
  return null;
}

/**
 * A leveraged or inverse ETF's daily target, read from its name ("Daily Semiconductor Bull 3X", "UltraPro Short QQQ",
 * "UltraShort QQQ", "2x Long NVDA Daily"); null for other ETFs. "Short-Term" and "Ultra-Short Income" are bond funds.
 */
export function leverage(name) {
  const times = Number(/(\d)x\b/i.exec(name)?.[1] ?? (/ultrapro/i.test(name) ? 3 : /ultrashort|\bultra\b(?!-short)/i.test(name) ? 2 : 1));
  const inverse = /\bbear\b|\binverse\b|ultrashort|\bshort\b(?![- ]term|\s+income|-duration)/i.test(name) && !/ultra-short/i.test(name);
  if (times === 1 && !inverse) return null;
  // Single-stock funds name the stock by its ticker ("TSLA Bull", "Long NVDA"); the others follow an index.
  const underlying = /\b(TSLA|NVDA|MU|SNDK|AAPL|AMZN|MSFT|META|GOOGL|AMD|PLTR|COIN|MSTR)\b/i.test(name) ? "da ação de referência" : "do índice";
  const sign = inverse ? "-" : "";
  return `${sign}${times}x o desempenho diário ${underlying} (${sign}${times * 100}%), com rebalanceamento diário`;
}

/** The day an ETF's shares first traded, from Yahoo Finance. Not used for stocks: Yahoo's B3 history starts in 2000. */
async function yahooFirstTrade(symbol) {
  const j = await get(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=1d&interval=1d`, { headers: browser });
  const first = j.chart?.result?.[0]?.meta?.firstTradeDate;
  return first ? new Date(first * 1000).toISOString().slice(0, 10) : null;
}

const etfSources = await readJSON("src/data/assets/etf-sources.json");
const roleBudgets = { etf: { lead: 3500, body: 6000 }, index: { lead: 2500, body: 3500 }, issuer: { lead: 1500, body: 2000 }, context: { lead: 1500, body: 2000 } };

/** The curated articles for an ETF, each titled with what it is to the ETF (its index, its issuer, or context). */
async function curatedETFArticles(ticker) {
  const articles = [];
  for (const { title, role, prefer } of etfSources.etfs[ticker] ?? []) {
    const article = await wikipedia("en", title, { ...roleBudgets[role], prefer });
    if (!article) continue;
    article.source.title = `Wikipedia (en): ${article.title} (${etfSources.roles[role]})`;
    articles.push({ ...article, role });
  }
  return articles;
}

// MARK: - Dossier

const keepUpper = new Set(["fii", "fiagro", "btg", "xp", "trx", "rbr", "vbi", "hsi", "ggr", "ii", "iii"]);
const lowerWords = new Set(["de", "da", "do", "das", "dos", "e", "em"]);
/** "MAXI RENDA FUNDO DE INVESTIMENTO IMOBILIÁRIO - FII" → "Maxi Renda Fundo de Investimento Imobiliário - FII". */
const fundName = (s) => s.toLowerCase().replace(/[^\s-]+/g, (w, at) =>
  keepUpper.has(w) ? w.toUpperCase() : at && lowerWords.has(w) ? w : w[0].toUpperCase() + w.slice(1));

const shareTypes = { 3: "Ação ordinária (ON)", 4: "Ação preferencial (PN)", 5: "Ação preferencial classe A (PNA)", 6: "Ação preferencial classe B (PNB)", 11: "Unit" };

/** Everything the generator writes from. Sources that fail are skipped and listed in `missing`. */
export async function collectSources(asset) {
  const { ticker, list } = asset;
  const stats = await assetStats(ticker, list);
  const currency = stats.currency;
  const symbol = list === "us-etfs" ? ticker : `${ticker}.SA`;
  const asOf = date(stats.asOf);
  const sources = [], characteristics = [], missing = [];
  const add = (s) => (s ? sources.push(s) - 1 : null);
  const characteristic = (label, value, at) => value && characteristics.push({ label, value, source: at });
  const attempt = async (name, work) => {
    try { return await work(); } catch (error) { missing.push(`${name}: ${error.message}`); return null; }
  };

  const yahoo = add(source(`Yahoo Finance: cotações históricas de ${ticker}`, `https://finance.yahoo.com/quote/${symbol}/history/`));
  const profile = { name: asset.name };

  if (list === "br-stocks") {
    const company = await attempt("B3", () => b3Company(ticker));
    const b3At = add(company?.source);
    const cnpj = company && formatCNPJ(company.detail.cnpj);
    const registry = cnpj && await attempt("CVM cadastro", () => cvmCompany(cnpj));
    const cvmAt = add(registry?.source);
    const wikidataId = cnpj && await attempt("Wikidata", () => wikidataIdForCompany(cnpj, [...new Set([ticker, ...company.codes])]));
    const wd = wikidataId && await attempt("Wikidata", () => wikidata(wikidataId));
    const wdAt = add(wd?.source);
    const ptTitle = wd?.articles.pt ?? await attempt("Wikipedia", () => findCompanyArticle([registry?.row.DENOM_COMERC, asset.name]));
    const pt = ptTitle && await attempt("Wikipedia pt", () => wikipedia("pt", ptTitle));
    add(pt?.source);
    if (wd?.articles.en && (pt?.text.length ?? 0) < 4000) add((await attempt("Wikipedia en", () => wikipedia("en", wd.articles.en, { body: 5000 })))?.source);
    for (const fact of cnpj ? (await attempt("CVM fatos relevantes", () => cvmMaterialFacts(cnpj))) ?? [] : []) add(fact);

    Object.assign(profile, {
      name: wd?.name ?? asset.name,
      legalName: registry?.row.DENOM_SOCIAL,
      type: shareTypes[ticker.match(/\d+$/)[0]],
      sector: company?.sector,
      segment: company?.segment,
      founded: date(registry?.row.DT_CONST),
      listedSince: date(company?.quotedSince),
      headquarters: registry?.headquarters,
      website: https(company?.detail.website),
    });
    characteristic("Razão social", registry?.row.DENOM_SOCIAL, cvmAt);
    characteristic("CNPJ", cnpj, cvmAt);
    characteristic("Setor (classificação B3)", company && [company.sector, company.segment].filter(Boolean).join(" / "), b3At);
    characteristic("Segmento de listagem", company?.listing, b3At);
    characteristic("Controle acionário", sentenceCase(registry?.row.CONTROLE_ACIONARIO), cvmAt);
    characteristic("Constituição", date(registry?.row.DT_CONST), cvmAt);
    characteristic("Sede", registry?.headquarters, cvmAt);
    characteristic("Cotada na B3 desde", date(company?.quotedSince), b3At);
    characteristic("Códigos de negociação", company?.codes.join(", "), b3At);
    characteristic("Auditor independente", registry?.row.AUDITOR, cvmAt);
    if (!registry?.row.DT_CONST) characteristic("Fundação", wd && date(wd.inception), wdAt);
  }

  if (list === "fiis") {
    const fund = await attempt("CVM informe mensal", () => cvmFund(ticker, asset.name));
    const cvmAt = add(fund?.source);
    const filings = fund && await attempt("FNET", () => fnetSources(fund.general.CNPJ_Fundo_Classe.replace(/\D/g, ""), ticker));
    for (const s of filings?.sources ?? []) add(s);
    const g = fund?.general;
    Object.assign(profile, {
      name: filings?.registeredName ? fundName(filings.registeredName) : asset.name,
      legalName: filings?.registeredName ?? g?.Nome_Fundo_Classe,
      sector: "Fundo de investimento imobiliário",
      segment: g?.Segmento_Atuacao,
      founded: date(g?.Data_Funcionamento),
      administrator: g?.Nome_Administrador,
      website: https(g?.Site),
    });
    characteristic("Nome", filings?.registeredName ?? g?.Nome_Fundo_Classe, filings?.registeredName ? cvmAt + 1 : cvmAt);
    characteristic("CNPJ", g?.CNPJ_Fundo_Classe, cvmAt);
    characteristic("Segmento de atuação", g?.Segmento_Atuacao, cvmAt);
    characteristic("Mandato", g?.Mandato, cvmAt);
    characteristic("Tipo de gestão", g?.Tipo_Gestao, cvmAt);
    characteristic("Administrador", g?.Nome_Administrador, cvmAt);
    characteristic("Início das atividades", date(g?.Data_Funcionamento), cvmAt);
    characteristic(`Patrimônio líquido (${fund?.month})`, bigMoney(fund?.netAssets), cvmAt);
    characteristic(`Cotistas (${fund?.month})`, fund?.shareholders && integer(fund.shareholders), cvmAt);
    characteristic(`Valor patrimonial da cota (${fund?.month})`, money(fund?.bookValue), cvmAt);
  }

  if (list === "us-etfs") {
    const curated = (await attempt("Wikipedia en", () => curatedETFArticles(ticker))) ?? [];
    const en = curated.find((a) => a.role === "etf")
      ?? (etfSources.etfs[ticker] ? null : await attempt("Wikipedia en", () => findETFArticle(ticker, [asset.name, stats.name])));
    const id = en && await attempt("Wikidata", () => wikidataIdByArticle("en", en.title));
    const wd = id && await attempt("Wikidata", () => wikidata(id));
    const wdAt = add(wd?.source);
    add(en?.source);
    for (const article of curated.filter((a) => a !== en)) add(article.source);
    if (wd?.articles.pt) add((await attempt("Wikipedia pt", () => wikipedia("pt", wd.articles.pt, { body: 3000 })))?.source);
    const firstTrade = await attempt("Yahoo primeiro pregão", () => yahooFirstTrade(symbol));
    if (firstTrade) {
      sources[yahoo].facts.push({ label: "Primeiro pregão das cotas", value: date(firstTrade) });
      sources[yahoo].events.push({ date: firstTrade, event: "Primeiro pregão das cotas do ETF na bolsa" });
    }
    Object.assign(profile, { founded: wd?.inception ? date(wd.inception) : date(firstTrade) });
    characteristic("Nome", asset.name, yahoo);
    characteristic("Lançamento", wd?.inception && date(wd.inception), wdAt);
    characteristic("Negociado desde", date(firstTrade), yahoo);
    const target = leverage(asset.name);
    if (target) characteristic("Objetivo diário", target, yahoo);
    characteristic("Bolsa", asset.exchange, yahoo);
    characteristic("Moeda", currency === "USD" ? "Dólar americano (US$)" : currency, yahoo);
  }

  // Market figures, all from the computed stats.
  characteristic(`Preço (${asOf})`, money(stats.price, currency), yahoo);
  characteristic("Volatilidade anual (12 meses)", `${percent(stats.volatility1y)} (${stats.volatilityLevel})`, yahoo);
  characteristic(`Beta (12 meses, contra o ${stats.beta1y.against})`, stats.beta1y.value?.toLocaleString("pt-BR", { minimumFractionDigits: 2 }), yahoo);
  if (stats.dividends?.payments12Months) characteristic("Dividend yield (12 meses)", percent(stats.dividends.yield12Months), yahoo);
  characteristic("Volume médio diário (3 meses)", bigMoney(stats.avgDailyTradedValue3m, currency), yahoo);

  // Dated events that come straight from the records, for the timeline.
  const events = sources.flatMap((s, at) => s.events.map((e) => ({ ...e, source: at })))
    .filter((e, i, all) => all.findIndex((x) => x.date === e.date && x.event === e.event) === i)
    .sort((a, b) => a.date.localeCompare(b.date));

  return {
    ticker, list, slug: asset.slug, path: asset.path, name: profile.name, collectedAt: today,
    profile: Object.fromEntries(Object.entries(profile).filter(([, v]) => v)),
    characteristics: characteristics.slice(0, 14),
    stats, sources, events, missing,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const asset = process.argv[2] && findAsset(process.argv[2]);
  if (!asset) {
    console.error("usage: node scripts/asset-sources.mjs <TICKER>   (a ticker from src/data/assets/*.json)");
    process.exit(1);
  }
  console.log(JSON.stringify(await collectSources(asset), null, 2));
}
