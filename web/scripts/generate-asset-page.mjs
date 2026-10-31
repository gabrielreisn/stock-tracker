// Writes asset pages (src/content/assets/<list>/<slug>.json) with a local model served by Ollama (Qwen 3.8 27B by
// default), from the public sources scripts/asset-sources.mjs gathers. The model only writes prose and picks links; what
// can be taken from the records (characteristics, profile facts, stats, sources, canonical path) is filled in by code,
// links are checked against the site's pages, and every timeline date must appear in the source it cites.
//
//   node scripts/generate-asset-page.mjs PETR4 [MXRF11 …]     one or more pages (overwrites)
//   node scripts/generate-asset-page.mjs --all                 every listed asset without a page yet
//   node scripts/generate-asset-page.mjs --all --list fiis --force
//   CYMBA_MODEL=gemma3:27b node scripts/generate-asset-page.mjs SPY     another Ollama model
//
// Needs Ollama running (`ollama serve`, or `brew services start ollama`) and the model pulled (`ollama pull qwen3.8:27b`).
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { z } from "zod";
import { catalog, collectSources, findAsset, leverage, lists, root } from "./asset-sources.mjs";
import { date, isoDate, percent, money, bigMoney } from "./pt-br.mjs";
import { advice, checkPage } from "./validate-asset-page.mjs";
import { describeIssues } from "../src/data/schema/asset-page.ts";

const modelName = process.env.CYMBA_MODEL ?? "qwen3.8:27b";
const ollama = process.env.OLLAMA_HOST ?? "http://127.0.0.1:11434";
const contextSize = 32_768;
// Good answers take 3.000 to 4.500 tokens; past this the model is rambling or stuck.
const maxAnswerTokens = 7_000;
const attempts = 2;
const kinds = { "br-stocks": "ação brasileira (B3)", fiis: "fundo imobiliário, FII (B3)", "us-etfs": "ETF americano", bdrs: "BDR: recibo negociado na B3, em reais, que representa ações de uma empresa listada no exterior" };
const listNames = { "br-stocks": "Ações brasileiras", fiis: "FIIs", "us-etfs": "ETFs americanos", bdrs: "BDRs" };
const today = new Date().toISOString().slice(0, 10);

// The sections of each kind of page: the same headings across pages, and a model writes better one subject at a time.
const sectionPlans = {
  "br-stocks": [
    { id: "negocio", heading: "Como a {name} ganha dinheiro", guide: "A atividade da companhia e de onde vem a receita, só com o que as fontes dizem." },
    { id: "controle-e-acoes", heading: "Controle e ações da {name}", guide: "O controle acionário, o segmento de listagem e os códigos de negociação (fontes B3 e CVM). Se houver ações ON e PN, explique em termos gerais a diferença (direito a voto, preferência nos proventos), sem comparar rentabilidade ou risco." },
    { id: "proventos", heading: "{ticker} paga dividendos?", guide: "Os proventos dos números calculados (valor, quantidade de pagamentos, dividend yield, último pagamento) e o que as fontes dizem sobre a remuneração aos acionistas. Link para o recurso de proventos. Não escreva sobre tributação." },
    { id: "desempenho", heading: "Desempenho da {ticker}", guide: "As rentabilidades dos números calculados, sempre com o período e a data. Link para a comparação com índices (Ibovespa, CDI)." },
    { id: "riscos", heading: "Riscos da {ticker}", guide: "Os riscos que as fontes mencionam e os riscos gerais do setor, a volatilidade e a maior queda. Sem opinar se o risco é alto ou baixo além do nível calculado." },
  ],
  fiis: [
    { id: "estrategia", heading: "Estratégia e portfólio do {ticker}", guide: "O tipo de fundo (papel, tijolo, híbrido, fundo de fundos), o segmento, a gestora e o administrador, o objetivo e os ativos da carteira segundo o relatório gerencial, com a data de referência." },
    { id: "rendimentos", heading: "Rendimentos do {ticker}", guide: "Os proventos dos números calculados e o dividend yield; a tributação só como o relatório gerencial ou outra fonte do dossiê descreve. Link para o recurso de proventos." },
    { id: "emissoes", heading: "Emissões de cotas, patrimônio e cotistas", guide: "As ofertas de cotas (eventos confirmados do FNET), o patrimônio líquido, o número de cotistas e o valor patrimonial da cota da CVM, com as datas." },
    { id: "desempenho", heading: "Desempenho do {ticker}", guide: "As rentabilidades dos números calculados, sempre com o período e a data. Link para a comparação com índices (IFIX, CDI)." },
    { id: "riscos", heading: "Riscos do {ticker}", guide: "Os riscos que as fontes mencionam e os riscos gerais do tipo de fundo (crédito para fundos de papel, vacância para fundos de tijolo, juros), a volatilidade e a maior queda." },
  ],
  bdrs: [
    { id: "negocio", heading: "Como a {name} ganha dinheiro", guide: "A atividade da empresa e de onde vem a receita, só com o que as fontes dizem." },
    { id: "como-funciona-o-bdr", heading: "Como funciona o BDR {ticker}", guide: "Em termos gerais: o BDR é um recibo negociado na B3, em reais, lastreado em ações da empresa no exterior e emitido por uma instituição depositária; o preço acompanha a ação original e o câmbio. Diga o tipo de programa e a ação original (bolsa e ticker) segundo as fontes, e a data de listagem na B3. Não fale de tributação nem de corretoras." },
    { id: "proventos", heading: "{ticker} paga dividendos?", guide: "Os proventos dos números calculados (valor, quantidade de pagamentos, dividend yield, último pagamento), lembrando que a empresa paga na moeda dela e o valor chega em reais. Se não houve proventos, diga isso." },
    { id: "desempenho", heading: "Desempenho do {ticker}", guide: "As rentabilidades dos números calculados, em reais, sempre com o período e a data; explique que elas incluem a variação do câmbio. Link para a comparação com índices (S&P 500, CDI)." },
    { id: "riscos", heading: "Riscos do {ticker}", guide: "Os riscos que as fontes mencionam sobre a empresa, o risco cambial, a liquidez do BDR na B3, a volatilidade e a maior queda." },
  ],
  "us-etfs": [
    { id: "como-funciona", heading: "Como o {ticker} funciona", guide: "O que o ETF replica, a emissora e o lançamento, segundo as fontes. Se for alavancado ou inverso, explique logo no começo o rebalanceamento diário e por que, em períodos longos, o resultado se afasta do múltiplo do índice." },
    { id: "composicao", heading: "Índice e composição do {ticker}", guide: "O índice ou ativo que o ETF segue e a composição, só com o que as fontes dizem." },
    { id: "investir-do-brasil", heading: "Como investir no {ticker} a partir do Brasil", guide: "Em termos gerais: comprando por uma conta numa corretora no exterior, ou com ETFs e BDRs da B3 que seguem o mesmo índice; o risco cambial de um ativo em dólar. Sem citar corretoras e sem falar de tributação." },
    { id: "desempenho", heading: "Desempenho do {ticker}", guide: "As rentabilidades dos números calculados em dólar, sempre com o período e a data. Link para a comparação com índices (S&P 500)." },
    { id: "riscos", heading: "Riscos do {ticker}", guide: "Os riscos que as fontes mencionam e os riscos gerais desse tipo de ETF, a volatilidade e a maior queda." },
  ],
};
const planFor = (asset, name) => sectionPlans[asset.list].map((s) => ({ ...s, heading: s.heading.replaceAll("{ticker}", asset.ticker).replaceAll("{name}", name) }));

// Written by code, not the model, on every leveraged or inverse ETF page (the page also shows it at the top).
const leveragedNotice = "ETF alavancado ou inverso: busca um múltiplo do desempenho de um único dia e é rebalanceado todos os dias, então em períodos maiores o resultado pode ser muito diferente desse múltiplo, e as perdas podem ser grandes.";

const pagePath = (asset) => `src/content/assets/${asset.list}/${asset.slug}.json`;
const allowedPaths = new Set([
  ...catalog.features.map((f) => f.path),
  ...Object.entries(lists).flatMap(([list, assets]) => assets.map((a) => catalog.site.assetPaths[list].replace("{slug}", a.slug))),
  ...Object.values(catalog.site.hubs),
  catalog.site.download,
]);

// MARK: - Prompt

/** The dossier as the model reads it: the asset, computed figures, numbered sources, dated events and link targets. */
function dossierText(asset, d, sourceTexts) {
  const s = d.stats, currency = s.currency, asOf = date(s.asOf);
  const per = asset.list === "br-stocks" ? "por ação" : asset.list === "bdrs" ? "por BDR" : "por cota";
  const returns = Object.entries({ "1y": "12 meses", "3y": "3 anos", "5y": "5 anos", "10y": "10 anos" })
    .filter(([k]) => s.returns[k] != null).map(([k, label]) => `${label} ${percent(s.returns[k])}`);
  const dividends = s.dividends?.payments12Months
    ? `${money(s.dividends.last12Months, currency, 4)} ${per} em ${s.dividends.payments12Months} pagamentos nos 12 meses até ${asOf} (dividend yield de ${percent(s.dividends.yield12Months)}). Último: ${money(s.dividends.lastPayment.amount, currency, 4)} em ${date(s.dividends.lastPayment.date)}.`
    : "nenhum nos últimos 12 meses.";
  const drawdown = s.maxDrawdown5y.drawdown ? `${percent(s.maxDrawdown5y.drawdown)}, do pico em ${date(s.maxDrawdown5y.from)} ao ponto mais baixo em ${date(s.maxDrawdown5y.to)}` : "sem queda relevante";
  const profileLabels = { name: "Nome", legalName: "Razão social / nome registrado", type: "Tipo", sector: "Setor", segment: "Segmento", founded: "Fundação / início", listedSince: "Cotada na B3 desde", headquarters: "Sede", administrator: "Administrador", website: "Site" };

  const out = [
    "# Ativo",
    `Ticker: ${asset.ticker}`,
    `Tipo de página: ${kinds[asset.list]}`,
    `Endereço desta página: ${asset.path} (não crie link para ele)`,
    ...Object.entries(d.profile).map(([k, v]) => `${profileLabels[k] ?? k}: ${v}`),
    "",
    `# Números calculados (fonte [0], Yahoo Finance, até ${asOf}). Copie exatamente.`,
    `- Preço em ${asOf}: ${money(s.price, currency)}`,
    `- Rentabilidade total com proventos: ${returns.join("; ")}`,
    `- Volatilidade anualizada (12 meses): ${percent(s.volatility1y)}, nível "${s.volatilityLevel}"`,
    s.beta1y.value == null
      ? "- Beta: não disponível"
      : asset.list === "bdrs"
        ? `- Beta da ação original (não do BDR) nos últimos 12 meses, contra o ${s.beta1y.against}: ${s.beta1y.value.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}. É o beta da ação no exterior, em dólares; o BDR em reais também sofre o efeito do câmbio.`
        : `- Beta (12 meses) contra o ${s.beta1y.against}: ${s.beta1y.value.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}`,
    `- Maior queda nos últimos 5 anos: ${drawdown}`,
    `- Proventos: ${dividends}`,
    s.avgDailyTradedValue3m ? `- Volume médio negociado por dia (3 meses): ${bigMoney(s.avgDailyTradedValue3m, currency)}` : null,
    "",
    "# Fontes (cite pelo número)",
  ];
  d.sources.forEach((source, i) => {
    out.push(`[${i}] ${source.title}`);
    for (const f of source.facts) out.push(`- ${f.label}: ${f.value}`);
    if (sourceTexts[i]) out.push('"""', sourceTexts[i], '"""');
  });
  out.push("", "# Seções a escrever (campo sections)");
  for (const section of planFor(asset, d.profile.name)) out.push(`- ${section.id}, "${section.heading}": ${section.guide}`);
  out.push("", "# Eventos confirmados (datas exatas, use na linha do tempo com a fonte)");
  for (const e of d.events) out.push(`- ${e.date}: ${e.event} [${e.source}]`);
  out.push("", "# Recursos do app (links permitidos)");
  for (const f of catalog.features.filter((f) => f.relevantFor.includes(asset.list))) {
    out.push(`- ${f.path} (${f.slug}): ${f.name}. ${f.summary} Quando linkar: ${f.linkWhen}`);
  }
  // The whole list of the asset's own kind, where related assets are; the most traded of the others, for comparisons.
  out.push("", "# Outros ativos com página (links permitidos)");
  for (const [list, all] of Object.entries(lists)) {
    const assets = list === asset.list ? all : all.slice(0, 20);
    out.push(`${listNames[list]}: ${assets.filter((a) => a.ticker !== asset.ticker)
      .map((a) => `${a.ticker} ${catalog.site.assetPaths[list].replace("{slug}", a.slug)} (${a.name})`).join("; ")}`);
  }
  return out.filter((l) => l != null).join("\n");
}

/** What the model writes. Everything else on the page comes from the dossier. */
function draftSchema(asset, d) {
  // Short fields get a limit about 1.5 times the page's (fit() trims to the page's later): without a grammar a model can
  // otherwise turn a name into paragraphs and never close the string.
  const short = (max) => z.string().max(max);
  const text = (min) => z.string().min(min);
  const profile = {
    "br-stocks": null,
    fiis: z.strictObject({ type: short(80), issuerOrManager: short(120) }),
    "us-etfs": z.strictObject({ type: short(80), issuerOrManager: short(120), trackedIndex: short(120), expenseRatio: short(80) }),
  }[asset.list];
  return z.strictObject({
    ...(profile ? { profile } : {}),
    summary: text(200),
    history: z.strictObject({
      overview: text(400),
      timeline: z.array(z.strictObject({ date: short(10), event: short(360), source: z.literal(d.sources.map((_, i) => i)) })).min(3).max(14),
    }),
    sections: z.strictObject(Object.fromEntries(planFor(asset, d.profile.name).map((s) => [s.id, text(200)]))),
    volatility: text(150),
    faq: z.array(z.strictObject({ question: short(200), answer: text(80).max(1000) })).min(5).max(7),
    internalLinks: z.strictObject({
      features: z.array(z.strictObject({ feature: z.enum(catalog.features.filter((f) => f.relevantFor.includes(asset.list)).map((f) => f.slug)), anchor: short(100), context: short(360) })).min(3).max(5),
      assets: z.array(z.strictObject({ ticker: z.enum(Object.values(lists).flat().map((a) => a.ticker).filter((t) => t !== asset.ticker)), reason: short(240) })).min(3).max(5),
    }),
    seo: z.strictObject({ title: short(90), description: short(230), h1: short(120), keywords: z.array(short(60)).min(3).max(8) }),
  });
}

/** The draft's shape as JSON Schema, for Ollama's constrained output or the prompt. */
function jsonSchema(schema) {
  const json = z.toJSONSchema(schema);
  delete json.$schema;
  return json;
}

// MARK: - From draft to page

/** Shortens text to `max` characters at a sentence, or else a word, boundary. */
function fit(text, max) {
  text = text.trim();
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const sentence = cut.lastIndexOf(". ");
  if (sentence > max * 0.5) return cut.slice(0, sentence + 1);
  return cut.slice(0, cut.lastIndexOf(" ")).replace(/[\s,;:–-]+$/, "");
}

/** Keeps links to the site's pages (lowercasing paths); anything else, including the page itself, becomes plain text. */
function fixLinks(text, self, report) {
  // The model sometimes writes a feature as "[proventos]" with no address: make it the real link.
  text = text.replace(/\[([a-z0-9-]+)\](?!\()/g, (all, slug) => {
    const feature = catalog.features.find((f) => f.slug === slug);
    return feature ? `[${feature.name}](${feature.path})` : slug;
  });
  return text.replace(/\[([^\]]+)\]\(([^)\s]*)\)/g, (all, label, href) => {
    const path = href.split("#")[0].toLowerCase();
    if (allowedPaths.has(path) && path !== self) return `[${label}](${path})`;
    report.droppedLinks.push(href);
    return label;
  });
}

const plain = (s) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
const monthsPt = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
const monthsEn = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

/** The date at the precision `text` (lowercased) supports: the day, the month, or just the year. */
function precision(when, text) {
  const [y, m, d] = when.split("-");
  const pt = monthsPt[+m - 1], en = monthsEn[+m - 1];
  if (d && [`${d}/${m}/${y}`, when, `${+d} de ${pt} de ${y}`, `${+d}º de ${pt} de ${y}`, `${en} ${+d}, ${y}`, `${+d} ${en} ${y}`].some((f) => text.includes(f))) return when;
  if (m && [`${m}/${y}`, `${y}-${m}`, `${pt} de ${y}`, `${en} ${y}`].some((f) => text.includes(f))) return `${y}-${m}`;
  return y;
}

// Figures a sentence can state: decimals ("72,8"), percentages and years.
const figures = /\d{1,3}(?:\.\d{3})*,\d+|\b\d+(?:,\d+)?\s?%|\b(?:1[89]\d{2}|20\d{2})\b/g;

/**
 * Whether the dossier states a figure: as written, in English notation ("0.0945%" for "0,0945%"), or, for an amount
 * in millions or billions, as the full number it rounds ("R$ 5,25 bilhões" for 5.252.427.200).
 */
function stated(figure, sentence, dossier) {
  const compact = figure.replace(/\s/g, "");
  if (dossier.includes(compact)) return true;
  if (dossier.includes(compact.replace(/[.,]/g, (c) => (c === "," ? "." : ",")))) return true;
  const scale = sentence.slice(sentence.indexOf(figure) + figure.length).match(/^\s*(bilh|milh)/)?.[1];
  if (!scale) return false;
  const [whole, fraction = ""] = compact.replace(/\./g, "").split(",");
  const digits = whole + fraction;
  const length = whole.length + (scale === "bilh" ? 9 : 6);
  return (dossier.match(/\d[\d.,]*\d/g) ?? []).some((run) => {
    const plain = run.replace(/[.,]/g, "");
    return plain.length === length && plain.startsWith(digits);
  });
}

/** Drops sentences with a figure that isn't in the dossier: the model may only restate numbers it was given. */
function grounded(text, dossier, report) {
  return text.split("\n").map((line) => line.split(/(?<=[.!?])\s+(?=[A-ZÀ-Ú"“(\[])/).filter((sentence) => {
    const unknown = (sentence.match(figures) ?? []).filter((f) => !stated(f, sentence, dossier));
    if (unknown.length) report.droppedSentences.push(sentence);
    return !unknown.length;
  }).join(" ")).join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

/** Links the first mention of each listed ticker (other than this page's) across the page's text. */
function linkTickers(texts, self) {
  const seen = new Set(texts.flatMap((t) => [...t.matchAll(/\[([A-Z0-9]{3,6})\]\(/g)].map((m) => m[1])));
  const paths = new Map(Object.entries(lists).flatMap(([list, assets]) => assets.map((a) => [a.ticker, catalog.site.assetPaths[list].replace("{slug}", a.slug)])));
  return texts.map((text) => text.replace(/(?<![[\w/])\b([A-Z]{3,5}\d{0,2})\b(?![\]\w])/g, (ticker) => {
    const path = paths.get(ticker);
    if (!path || path === self || seen.has(ticker)) return ticker;
    seen.add(ticker);
    return `[${ticker}](${path})`;
  }));
}

function assemble(asset, d, draft, dossier) {
  const report = { droppedLinks: [], droppedEvents: [], droppedSentences: [] };
  const self = asset.path;
  const prose = (text) => fixLinks(grounded(text, dossier, report), self, report);
  const stats = d.stats;

  // Timeline: the year must appear in a source that also mentions the event (the cited one, or else the first that
  // does), and the date keeps only the precision that source states.
  const cited = d.sources.map((s) => [s.title, ...s.facts.map((f) => f.value), ...s.events.map((e) => e.date), s.text].join(" ").toLowerCase());
  const timeline = [];
  for (const e of draft.history.timeline) {
    const when = e.date.trim().match(/^\d{4}(-\d{2}(-\d{2})?)?/)?.[0] ?? isoDate(e.date.trim());
    const words = plain(e.event).split(/\W+/).filter((w) => w.length >= 5);
    const mentions = (i) => cited[i]?.includes(when.slice(0, 4)) && (i === e.source || words.filter((w) => plain(cited[i]).includes(w)).length >= 2);
    const at = !when ? -1 : mentions(e.source) ? e.source : cited.findIndex((_, i) => mentions(i));
    if (at < 0) { report.droppedEvents.push(`${e.date} ${e.event} [${e.source}]`); continue; }
    if (timeline.some((t) => t.event === e.event)) continue;
    timeline.push({ date: precision(when, cited[at]), event: fit(e.event, 240), source: at });
  }
  for (const e of d.events) {
    if (timeline.length >= 3) break;
    if (!timeline.some((t) => t.date === e.date)) timeline.push({ date: e.date, event: e.event, source: e.source });
  }
  timeline.sort((a, b) => a.date.localeCompare(b.date));

  const sections = planFor(asset, d.profile.name).map((s) => ({ id: s.id, heading: fit(s.heading, 80), body: prose(draft.sections[s.id]) }));

  // An anchor that is the feature's slug reads as code; use the feature's name instead.
  const features = draft.internalLinks.features.filter((f, i, all) => all.findIndex((x) => x.feature === f.feature) === i)
    .map((f) => ({
      feature: f.feature,
      anchor: fit(/^[a-z0-9-]+$/.test(f.anchor.trim()) ? catalog.features.find((x) => x.slug === f.feature).name : f.anchor, 70),
      context: fit(f.context.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"), 240),
    }));
  const assets = draft.internalLinks.assets.filter((a, i, all) => all.findIndex((x) => x.ticker === a.ticker) === i)
    .map((a) => ({ ticker: a.ticker, list: findAsset(a.ticker).list, reason: fit(a.reason, 160) }));

  // Questions that ask for advice ("X é um bom investimento?") and answers left too short by grounding are dropped
  // while enough questions remain.
  let faq = draft.faq.map((f) => ({ question: fit(f.question, 140), answer: fit(prose(f.answer), 700) }));
  const kept = faq.filter((f) => f.answer.length >= 80 && !advice.test(f.question) && !advice.test(f.answer));
  if (kept.length >= 5) faq = kept;
  const volatility = { level: stats.volatilityLevel, explanation: prose(draft.volatility) };
  let overview = prose(draft.history.overview);

  // Every listed ticker the text mentions becomes a link to its page, once.
  const linkedTexts = linkTickers([overview, ...sections.map((s) => s.body), volatility.explanation, ...faq.map((f) => f.answer)], self);
  overview = linkedTexts.shift();
  for (const s of sections) s.body = linkedTexts.shift();
  volatility.explanation = linkedTexts.shift();
  for (const f of faq) f.answer = linkedTexts.shift();

  // The pages exist to show the app where it helps: when the model linked fewer than three features in the text,
  // close with a short section built from the links it chose.
  const featurePath = (slug) => catalog.features.find((f) => f.slug === slug).path;
  const linked = new Set([volatility.explanation, overview, ...sections.map((s) => s.body), ...faq.map((f) => f.answer)]
    .flatMap((t) => [...t.matchAll(/\]\((\/recursos\/[^)]+)\)/g)].map((m) => m[1])));
  if (linked.size < 3) {
    sections.push({
      id: "acompanhe-no-app",
      heading: `Como acompanhar ${asset.ticker} no app`,
      body: [`Para quem tem ${asset.ticker} na carteira, o [app de Mac para acompanhar investimentos](${catalog.site.download}) oferece:`, "",
        ...features.map((f) => `- [${f.anchor}](${featurePath(f.feature)}): ${f.context}`)].join("\n"),
    });
  }

  let title = draft.seo.title.trim();
  if (!title.startsWith(asset.ticker)) title = `${asset.ticker}: ${title}`;
  title = fit(title, 60);
  if (title.length < 20) title = fit(`${asset.ticker}: ${d.name}`, 60);
  let description = fit(draft.seo.description, 155);
  if (description.length < 80) description = fit(draft.summary.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"), 155);

  const page = {
    ticker: asset.ticker,
    slug: asset.slug,
    list: asset.list,
    locale: "pt-BR",
    updatedAt: today,
    datePublished: today,
    seo: { title, description, h1: fit(draft.seo.h1, 80), canonicalPath: self, keywords: [...new Set(draft.seo.keywords.map((k) => k.trim()))].slice(0, 12) },
    summary: fit(grounded(draft.summary.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"), dossier, report), 600),
    // The model's profile fields are names, not prose: keep their first sentence.
    ...(d.entity ? { entity: d.entity } : {}),
    profile: Object.fromEntries(Object.entries({ ...Object.fromEntries(Object.entries(draft.profile ?? {}).map(([k, v]) => [k, v.split(/\.\s/)[0].trim()])), ...d.profile })
      .filter(([k, v]) => v?.trim() && !(k === "website" && !v.startsWith("https://")))),
    characteristics: d.characteristics,
    stats,
    volatility,
    history: { overview, timeline: timeline.slice(0, 18) },
    sections: sections.slice(0, 8),
    faq,
    internalLinks: { features, assets },
    sources: d.sources.map(({ title, url, accessedAt }) => ({ title, url, accessedAt })),
    disclaimer: `Conteúdo informativo, não é recomendação de investimento.${asset.list === "us-etfs" && leverage(asset.name) ? ` ${leveragedNotice}` : ""} Rentabilidade passada não garante rentabilidade futura. Dados de mercado do Yahoo Finance até ${date(stats.asOf)}; demais fontes listadas abaixo, consultadas em ${date(today)}.`,
  };
  return { page, report };
}

// MARK: - Generation

// Ollama constrains the output to the schema when the model supports it; otherwise (Qwen 3.8 on Ollama 0.40: "structured
// output is unavailable") the schema goes in the prompt and the answer is checked against it.
let constrained = true;
const jsonInstructions = (schema) => `\n\n# Formato da resposta\nResponda só com um objeto JSON, sem \`\`\` e sem texto antes ou depois, que siga este JSON Schema (respeite minLength, minItems e maxItems):\n${JSON.stringify(schema)}`;

/** The first complete JSON object in an answer, ignoring code fences and anything written around or after it. */
function parseJSON(answer) {
  const start = answer.indexOf("{");
  if (start < 0) throw new Error("the answer has no JSON object");
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < answer.length; i++) {
    const c = answer[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
    } else if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return JSON.parse(answer.slice(start, i + 1));
  }
  throw new Error("the answer's JSON object is incomplete");
}

/** One chat completion from Ollama, in the shape of `schema`, with thinking off. Streams to show progress. */
async function complete(system, user, schema) {
  const stop = new AbortController();
  const response = await fetch(`${ollama}/api/chat`, {
    method: "POST",
    signal: stop.signal,
    body: JSON.stringify({
      model: modelName,
      messages: [{ role: "system", content: system }, { role: "user", content: constrained ? user : user + jsonInstructions(schema) }],
      ...(constrained ? { format: schema } : {}),
      think: false,
      stream: true,
      keep_alive: "10m",
      options: { num_ctx: contextSize, num_predict: maxAnswerTokens, temperature: 0.6, top_p: 0.8, top_k: 20 },
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    if (constrained && /structured output is unavailable/.test(text)) {
      constrained = false;
      console.log(`  ${modelName} can't constrain its output to a schema: the schema goes in the prompt instead`);
      return complete(system, user, schema);
    }
    throw new Error(`Ollama: HTTP ${response.status} ${text}`);
  }
  const started = Date.now();
  let answer = "", pending = "", chunks = 0, final = {}, looping = false;
  try {
    for await (const bytes of response.body) {
      pending += Buffer.from(bytes).toString("utf8");
      const lines = pending.split("\n");
      pending = lines.pop();
      for (const line of lines.filter(Boolean)) {
        const chunk = JSON.parse(line);
        if (chunk.error) throw new Error(`Ollama: ${chunk.error}`);
        answer += chunk.message?.content ?? "";
        if (chunk.done) final = chunk;
        chunks++;
        if (process.stdout.isTTY && chunks % 50 === 0) process.stdout.write(`\r  writing: ${chunks} tokens, ${(chunks / ((Date.now() - started) / 1000)).toFixed(1)} tokens/s`);
        // A model stuck in a loop repeats the same passage, or writes only whitespace and commas after the JSON:
        // stop it now rather than at the token limit.
        if (chunks % 50 === 0 && answer.length > 1000 &&
            (answer.split(answer.slice(-300)).length > 3 || !/[\p{L}\d]/u.test(answer.slice(-200)))) {
          looping = true;
          stop.abort();
        }
      }
    }
  } catch (error) {
    if (!looping) throw error;
  }
  if (looping) {
    console.log(`${process.stdout.isTTY ? "\r" : ""}  stopped after ${chunks} tokens: the model was repeating itself${" ".repeat(10)}`);
    return { answer, cut: "the model was repeating itself" };
  }
  const tokens = final.eval_count ?? chunks;
  const rate = final.eval_duration ? tokens / (final.eval_duration / 1e9) : tokens / ((Date.now() - started) / 1000);
  console.log(`${process.stdout.isTTY ? "\r" : ""}  written: ${tokens} tokens in ${((Date.now() - started) / 1000).toFixed(1)}s (prompt ${final.prompt_eval_count ?? "?"} tokens, ${rate.toFixed(1)} tokens/s)${" ".repeat(10)}`);
  return { answer, cut: final.done_reason === "length" ? `the answer passed ${maxAnswerTokens} tokens` : null };
}

async function generate(asset, systemPrompt) {
  const started = Date.now();
  const seconds = (from) => `${((Date.now() - from) / 1000).toFixed(1)}s`;
  console.log(`\n${asset.ticker} (${asset.list})`);

  const d = await collectSources(asset);
  console.log(`  sources: ${d.sources.length} in ${seconds(started)}${d.missing.length ? `, missing ${d.missing.join("; ")}` : ""}`);

  // Fit the dossier in the context (Ollama would silently drop the start of an oversized prompt): shorten the
  // longest excerpt until the prompt, at a conservative 3 characters per token, leaves room for the answer.
  const tokens = (text) => Math.ceil(text.length / 3);
  const sourceTexts = d.sources.map((s) => s.text);
  let user = dossierText(asset, d, sourceTexts);
  const budget = contextSize - maxAnswerTokens - tokens(systemPrompt) - 500;
  while (tokens(user) > budget) {
    const longest = sourceTexts.reduce((best, t, i) => (t.length > sourceTexts[best].length ? i : best), 0);
    sourceTexts[longest] = sourceTexts[longest].slice(0, Math.floor(sourceTexts[longest].length * 0.7)) + " […]";
    user = dossierText(asset, d, sourceTexts);
  }

  const drafts = new URL(`.cache/drafts/${asset.list}/`, root);
  await mkdir(drafts, { recursive: true });
  const shape = draftSchema(asset, d);
  const schema = jsonSchema(shape);
  let feedback = "", result;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    let draft;
    try {
      const { answer, cut } = await complete(systemPrompt, user + feedback, schema);
      await writeFile(new URL(`${asset.slug}.answer-${attempt}.txt`, drafts), answer);
      // A reply stopped after its JSON closed (trailing whitespace) is still usable.
      let json;
      try {
        json = parseJSON(answer);
      } catch (error) {
        throw new Error(cut ? `cut off: ${cut}` : error.message);
      }
      const parsed = shape.safeParse(json);
      if (!parsed.success) throw new Error(describeIssues(parsed.error).join("; "));
      draft = parsed.data;
    } catch (error) {
      if (attempt === attempts) throw error;
      console.log(`  attempt ${attempt}: ${error.message}`);
      feedback = `\n\n# Corrija\nA resposta anterior não seguiu o formato pedido: ${error.message}. Escreva de novo.`;
      continue;
    }
    result = { draft, ...assemble(asset, d, draft, user.replace(/\s/g, "")) };
    result.check = checkPage(result.page, pagePath(asset));
    if (!result.check.problems.length) break;
    console.log(`  attempt ${attempt}: ${result.check.problems.join("; ")}`);
    feedback = `\n\n# Corrija\nA versão anterior desta página teve estes problemas: ${result.check.problems.join("; ")}. Escreva de novo, corrigindo-os.`;
  }

  await writeFile(new URL(`${asset.slug}.dossier.json`, drafts), JSON.stringify(d, null, 2));
  await writeFile(new URL(`${asset.slug}.draft.json`, drafts), JSON.stringify(result.draft, null, 2));

  const { page, report, check } = result;
  if (report.droppedEvents.length) console.log(`  timeline: left out ${report.droppedEvents.length} event(s) whose date isn't in the cited source`);
  if (report.droppedSentences.length) console.log(`  grounding: removed ${report.droppedSentences.length} sentence(s) with figures not in the sources:\n${report.droppedSentences.map((x) => `    - ${x}`).join("\n")}`);
  if (report.droppedLinks.length) console.log(`  links: removed ${[...new Set(report.droppedLinks)].join(", ")}`);
  for (const w of check.warnings) console.log(`  warning: ${w}`);
  if (check.problems.length) {
    const rejected = new URL(`${asset.slug}.page.json`, drafts);
    await writeFile(rejected, JSON.stringify(page, null, 2));
    console.log(`  ✗ not written, still invalid: ${check.problems.join("; ")}\n    (kept in ${rejected.pathname})`);
    return false;
  }
  const file = new URL(pagePath(asset), root);
  // A regenerated page keeps the date it was first published.
  const previous = await readFile(file, "utf8").then(JSON.parse, () => null);
  if (previous) page.datePublished = previous.datePublished ?? previous.updatedAt;
  await mkdir(new URL(".", file), { recursive: true });
  await writeFile(file, JSON.stringify(page, null, 2) + "\n");
  console.log(`  ✓ ${pagePath(asset)} in ${seconds(started)}`);
  return true;
}

// MARK: - Command line

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : null);
const listFilter = option("--list");
const tickers = args.filter((a, i) => !a.startsWith("--") && args[i - 1] !== "--list");

let assets;
if (flag("--all")) {
  assets = Object.keys(lists).filter((l) => !listFilter || l === listFilter).flatMap((l) => lists[l].map((a) => findAsset(a.ticker)));
  if (!flag("--force")) {
    const exists = await Promise.all(assets.map((a) => stat(new URL(pagePath(a), root)).then(() => true, () => false)));
    const skipped = assets.filter((_, i) => exists[i]).length;
    assets = assets.filter((_, i) => !exists[i]);
    if (skipped) console.log(`${skipped} page(s) already exist, skipped (--force to rewrite them).`);
  }
} else {
  assets = tickers.map((t) => findAsset(t) ?? (console.error(`${t} isn't in src/data/assets/*.json`), process.exit(1)));
}
if (!assets.length) {
  console.error(flag("--all") ? "Nothing to generate." : "usage: pnpm assets:generate <TICKER> [TICKER…]   |   pnpm assets:generate:all [--list fiis] [--force]");
  process.exit(flag("--all") ? 0 : 1);
}

const installed = await fetch(`${ollama}/api/tags`).then((r) => r.json(), () => null);
if (!installed) {
  console.error(`Ollama isn't running at ${ollama}. Start it with \`ollama serve\` (or \`brew services start ollama\`).`);
  process.exit(1);
}
if (!installed.models.some((m) => m.name === modelName || m.name === `${modelName}:latest`)) {
  console.error(`Ollama doesn't have ${modelName}. Download it with \`ollama pull ${modelName}\`.`);
  process.exit(1);
}
const systemPrompt = await readFile(new URL("scripts/asset-page-prompt.md", root), "utf8");
console.log(`Writing ${assets.length} page(s) with ${modelName} on Ollama.`);

let written = 0;
const failed = [];
for (const asset of assets) {
  const ok = await generate(asset, systemPrompt).catch((error) => (console.log(`  ✗ ${error.message}`), false));
  if (ok) written++; else failed.push(asset.ticker);
}
// Free the model's memory now instead of after keep_alive.
await fetch(`${ollama}/api/generate`, { method: "POST", body: JSON.stringify({ model: modelName, keep_alive: 0 }) }).catch(() => {});
console.log(`\n${written} written${failed.length ? `, ${failed.length} failed: ${failed.join(", ")}` : ""}.`);
process.exit(failed.length ? 1 : 0);
