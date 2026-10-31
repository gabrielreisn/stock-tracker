---
name: asset-page
description: Generates the data for one asset page of Cymba's website (a Brazilian stock, a US ETF or a FII) from a ticker — characteristics, computed volatility and returns, a sourced history, FAQ, and internal links that promote Cymba's features. Use when asked to write, generate, research or update an asset page, e.g. "gera a página da PETR4", "asset page for SPY", "/asset-page MXRF11".
---

# Asset page

Turns a ticker into `web/src/content/assets/<list>/<slug>.json`, the data behind a page like `/acoes/petr4`. The
website renders it later; this skill only produces the data. Pages are in **Brazilian Portuguese**: the audience is
the Brazilian investor searching for the ticker on Google or asking an AI assistant about it.

Every page has three jobs, in this order:
1. **Be the most useful, accurate page about the asset**, with facts a reader or an AI engine can trust and cite.
2. **Rank and get cited** (SEO and GEO): direct answers, specific facts with dates, named entities, sources.
3. **Lead to Cymba**: internal links that show, in context, how the app helps someone who holds this asset.

## Inputs

A ticker, and optionally its list. Find it in `web/src/data/assets/br-stocks.json`, `us-etfs.json` or `fiis.json`.
If the ticker isn't in any list, stop and say so: the lists are the site's pages, refreshed by
`node scripts/most-traded.mjs`.

## Workflow

Work from `web/`.

1. **Numbers first.** Run `node scripts/asset-stats.mjs <TICKER> <list>` and put its JSON output in `stats` without
   changing it. Every return, volatility, drawdown, beta, dividend and liquidity figure in the text comes from it.
   Never estimate, round differently or "update" one of these numbers from memory. Write them the Brazilian way
   (`29,98%`, `R$ 52,20`) and say the date ("até 29/10/2026").
   - If a figure looks wrong (for example a renamed ticker whose history starts at a strange point, or a 1-year
     return far outside the asset's usual range), check the price history before using it, and say in the text
     what you found, or leave that figure out.
2. **Research.** Start from `node scripts/asset-sources.mjs <TICKER>`: it gathers the public records (B3, CVM registry
   and material facts, CVM monthly FII report, FNET offerings and the latest management report, Wikidata,
   Wikipedia) with their URLs, and builds the characteristics table from them. Use its `characteristics` as they are.
   Then use web search and web fetch for what it lacks. Prefer primary sources, in this order:
   - **Stocks:** the company's investor relations site (RI), CVM filings (rad.cvm.gov.br, Formulário de
     Referência), B3.
   - **FIIs:** the fund's monthly report (relatório gerencial), its regulation, and B3 or CVM fund pages.
   - **ETFs:** the issuer's fund page (State Street SPDR, iShares, Vanguard, Invesco…) and the index provider.

   News outlets are fine for events, with their date. Wikipedia only to find primary sources, not as the only source
   of a fact. Write down every source you use, with the date you accessed it.
3. **Write the page** following the Zod schema in `web/src/data/schema/asset-page.ts` and the rules below.
4. **Validate.** Run `node scripts/validate-asset-page.mjs src/content/assets/<list>/<slug>.json` and fix every
   error. Then read the warnings: fix advice-like wording, and keep a feature link the validator calls "not marked
   relevant" only if the text really justifies it.
5. **Report** in a few lines: the file written, sources used, facts you couldn't confirm (and left out), and any
   figure from the stats that needed a caveat.

## Writing rules

**Accuracy**
- Every fact in `characteristics` and every `timeline` event points to a source (`source`: an index into `sources`).
- Facts that change (CEO, controlling shareholder, number of properties, expense ratio, vacancy) carry their date.
- If sources disagree, use the primary one. If you can't confirm a fact, leave it out rather than hedge it.

**SEO and GEO** (being found by search, and being quoted by AI answer engines)
- `summary`: 40–90 words that answer "o que é <TICKER>?" on their own. Include the company or fund name, what it
  does, its sector or strategy, and one dated figure. AI engines lift this paragraph verbatim, so no "neste artigo".
- `seo.title` starts with the ticker and says what the page is: "PETR4: história, dividendos e volatilidade".
  `seo.description` is a sentence a person would click, not a list of keywords.
- Headings and FAQ questions use the words people search for: "PETR4 paga dividendos?", "Qual a diferença entre
  PETR3 e PETR4?", "MXRF11 é de papel ou de tijolo?", "SPY ou IVV?".
- The first sentence of each FAQ answer answers it directly; the rest adds context.
- Prefer specific, quotable statements ("fundada em 1953", "taxa de administração de 0,09% ao ano, segundo a
  State Street") over adjectives. No superlatives you can't source ("a maior", "a melhor").
- Name entities fully the first time (Petróleo Brasileiro S.A. – Petrobras; Kinea Investimentos; State Street
  Global Advisors).

**History** (the core of the page)
- `history.overview`: 2–4 paragraphs on how the company or fund came to be what it is: origin, turning points,
  crises, mergers, strategy changes, and what they meant for shareholders. Tell it as a story, with dates.
- `history.timeline`: 3–18 dated events, each sourced. For FIIs: launch, offerings (emissões), major acquisitions
  or sales, manager changes. For ETFs: launch, index, notable milestones (assets, splits, fee changes).

**Volatility**
- `volatility.level` is `stats.volatilityLevel`. The explanation interprets it: the annualized volatility, the beta
  against its index, the worst drawdown with its start and end dates and what drove it (sourced), and how that
  compares to what's typical for its kind of asset. Inform, don't advise.

**Compliance: information, not advice**
- Don't recommend buying, selling or holding, and don't give price targets or say whether it's a good time. The
  validator flags the usual phrasings.
- Past returns are described as past ("rendeu X% nos últimos 12 meses até <data>"), never as expectations.
- `disclaimer`: "Conteúdo informativo, não é recomendação de investimento. Rentabilidade passada não garante
  rentabilidade futura. Dados de mercado de <fonte> até <data>."

## By kind of asset

**Brazilian stocks (`br-stocks`, path `/acoes/<slug>`)**
- Business model and where the revenue comes from, controlling shareholders, and share classes (ON/PN/units: link
  to the other class when it's in the list).
- Dividend and JCP history and policy (stats has the last 12 months).
- Main risks: commodity prices, regulation, government influence, debt.
- Peers and the Ibovespa.

**US ETFs (`us-etfs`, path `/etfs/<slug>`)**
- The index it tracks, the issuer, the expense ratio (sourced), top holdings or composition, and launch date.
- **Leveraged and inverse ETFs** (SOXL, TQQQ, SQQQ, SOXS…): explain the daily reset and the decay it causes over
  longer periods, plainly, early in the page.
- How a Brazilian investor gets exposure (an account abroad, or ETFs and BDRs listed on B3 that track the same
  index), currency risk, and the S&P 500 comparison. Don't name a specific broker.

**FIIs (`fiis`, path `/fiis/<slug>`)**
- Type (tijolo, papel, híbrido, fundo de fundos) and segment (logística, shoppings, lajes corporativas, CRI…), the
  manager and administrator, and portfolio highlights from the latest monthly report, dated.
- Monthly income: stats has the last 12 months. Explain the income tax exemption for individuals with its
  conditions, as the law and the fund's own documents state them, without promising it applies to the reader.
- The IFIX as its reference index.

## Internal links to Cymba

The feature catalog is `web/src/data/app-features.json`. It lists each feature's path, what it does, which asset
lists it's relevant for, and when to link it. Describe a feature **only** as its `summary` does: never promise
something the app doesn't do.

- `internalLinks.features`: 3–6 features, each with an anchor text and one sentence tying it to *this* asset.
  For example, for PETR4: "Acompanhe os dividendos e JCP da PETR4, com data com e data de pagamento, em
  [proventos](/recursos/proventos)."
- **At least three of those links also appear inside the prose** (sections, volatility, history or FAQ answers),
  where they help the reader:
  - Proventos where dividends are discussed.
  - Comparação com índices where the asset is compared with the Ibovespa, IFIX, S&P 500 or CDI.
  - Alertas de preço where volatility is explained.
  - Assistente de IA or carteira consolidada near the end.
- `internalLinks.assets`: 3–6 related pages from the three lists. Good picks:
  - The other share class.
  - Peers in the same sector.
  - FIIs in the same segment.
  - ETFs on the same index, or an alternative.

  Link at least two of them inline, as `[PETR3](/acoes/petr3)`.
- Links are relative paths: `/recursos/<feature>`, `/acoes/<slug>`, `/etfs/<slug>`, `/fiis/<slug>`, the hubs
  `/acoes`, `/etfs` and `/fiis`, and `/download`. Never link a page to itself.
- No "clique aqui"; the anchor says where it goes. Keep the tone informative: the links earn their click by being
  useful at that point of the text, not by selling.

## Output

Write the JSON to `web/src/content/assets/<list>/<slug>.json` (create the folder if needed), with `updatedAt` set
to today's date. One page per run unless asked for more. When asked for many, generate them one at a time, each
with its own research and validation.
