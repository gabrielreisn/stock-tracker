import { z } from "zod";

// An asset page (stock, US ETF or FII), written in Brazilian Portuguese, as stored in
// src/content/assets/<list>/<slug>.json. Shared by the website (types and parsing) and the scripts that write and check
// pages (scripts/generate-asset-page.mjs, scripts/validate-asset-page.mjs), which import this file directly: Node runs
// it by stripping the types, so it only uses syntax that can be erased.

export const assetLists = ["br-stocks", "us-etfs", "fiis", "bdrs"] as const;
export const volatilityLevels = ["baixa", "moderada", "alta", "muito alta"] as const;

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const https = z.string().regex(/^https:\/\//);

/** The output of scripts/asset-stats.mjs, copied without changes. */
export const assetStatsSchema = z.object({
  ticker: z.string(),
  list: z.enum(assetLists),
  asOf: isoDate,
  source: z.string(),
  name: z.string().nullable(),
  currency: z.string(),
  price: z.number(),
  historyStarts: isoDate,
  returns: z.object({ "1y": z.number().nullable(), "3y": z.number().nullable(), "5y": z.number().nullable(), "10y": z.number().nullable() }),
  volatility1y: z.number(),
  volatilityLevel: z.enum(volatilityLevels),
  maxDrawdown5y: z.object({ drawdown: z.number(), from: isoDate.nullable(), to: isoDate.nullable() }),
  beta1y: z.object({ value: z.number().nullable(), against: z.string() }),
  dividends: z.object({
    last12Months: z.number(),
    payments12Months: z.number().int(),
    yield12Months: z.number(),
    lastPayment: z.object({ date: isoDate, amount: z.number() }),
  }).nullable(),
  avgDailyTradedValue3m: z.number().nullable(),
});

/**
 * What the page is about, as structured data for JSON-LD: a company (stocks) or a fund (FIIs, ETFs). Collected from
 * the records by scripts/asset-sources.mjs, never written by the model.
 */
export const assetEntitySchema = z.strictObject({
  kind: z.enum(["Corporation", "InvestmentFund"]),
  name: z.string(),
  legalName: z.string().optional(),
  ticker: z.string().regex(/^([A-Z]{4} )?[A-Z0-9.]+$/).describe("Exchange MIC, a space, the ticker: BVMF PETR4, ARCX SPY (just the ticker when the exchange is unknown)"),
  isin: z.string().regex(/^[A-Z]{2}[A-Z0-9]{9}\d$/).optional(),
  taxId: z.string().optional().describe("CNPJ"),
  foundingDate: z.string().regex(/^\d{4}(-\d{2}(-\d{2})?)?$/).optional(),
  address: z.strictObject({ locality: z.string(), region: z.string().optional(), country: z.string().length(2) }).optional(),
  website: https.optional().describe("The company's or fund's own site"),
  provider: z.strictObject({ name: z.string(), url: https.optional(), sameAs: z.array(https).optional() }).optional()
    .describe("FIIs: the administrator (CVM). ETFs: the issuer."),
  wikidata: z.string().regex(/^Q\d+$/).optional(),
  sameAs: z.array(https).describe("Pages about the same company or fund: Wikidata, Wikipedia, B3, FNET"),
});

export const assetPageSchema = z.strictObject({
  ticker: z.string().regex(/^[A-Z0-9.]{2,12}$/),
  slug: z.string().regex(/^[a-z0-9-]+$/),
  list: z.enum(assetLists),
  locale: z.literal("pt-BR"),
  updatedAt: isoDate,
  /** The first time the page was written; kept when it's regenerated. */
  datePublished: isoDate.optional(),

  seo: z.strictObject({
    title: z.string().min(20).max(60).describe("Starts with the ticker. No clickbait."),
    description: z.string().min(80).max(155),
    h1: z.string().max(80),
    canonicalPath: z.string().regex(/^\/(acoes|etfs|fiis|bdrs)\/[a-z0-9-]+$/),
    keywords: z.array(z.string()).max(12).optional(),
  }),

  summary: z.string().min(200).max(600)
    .describe("Answer-first paragraph (40–90 words) that an AI answer engine can quote as is: what the asset is, its sector or strategy, and one figure with its date."),

  entity: assetEntitySchema.optional(),

  profile: z.strictObject({
    name: z.string(),
    legalName: z.string().optional(),
    type: z.string().describe("e.g. Ação preferencial (PN), Unit, ETF de índice, ETF alavancado, FII de tijolo — logística, FII de papel"),
    sector: z.string().optional(),
    segment: z.string().optional(),
    founded: z.string().optional(),
    listedSince: z.string().optional(),
    headquarters: z.string().optional(),
    issuerOrManager: z.string().optional().describe("ETF issuer, or FII manager (gestora)"),
    administrator: z.string().optional().describe("FII administrator"),
    trackedIndex: z.string().optional().describe("ETFs: the index replicated"),
    expenseRatio: z.string().optional().describe("ETFs: taxa de administração, with its source in sources"),
    website: https.optional(),
  }),

  characteristics: z.array(z.strictObject({
    label: z.string(),
    value: z.string(),
    source: z.number().int().min(0).optional().describe("Index in sources"),
  })).min(4).max(14).describe("Key facts table."),

  stats: assetStatsSchema,

  volatility: z.strictObject({
    level: z.enum(volatilityLevels),
    explanation: z.string().min(150).describe("Markdown. Uses stats: volatility, beta, worst drawdown with its dates, and what drove it."),
  }),

  history: z.strictObject({
    overview: z.string().min(400).describe("Markdown, 2–4 paragraphs."),
    timeline: z.array(z.strictObject({
      date: z.string().regex(/^\d{4}(-\d{2}(-\d{2})?)?$/),
      event: z.string().max(240),
      source: z.number().int().min(0),
    })).min(3).max(18),
  }),

  sections: z.array(z.strictObject({
    id: z.string().regex(/^[a-z0-9-]+$/),
    heading: z.string().max(80),
    body: z.string().min(200).describe("Markdown. Internal links as [texto](/recursos/...) or [PETR3](/acoes/petr3)."),
  })).min(3).max(8).describe("Body sections, e.g. Como a empresa ganha dinheiro / Como o ETF funciona / Portfólio do fundo, Dividendos, Riscos."),

  faq: z.array(z.strictObject({
    question: z.string().max(140),
    answer: z.string().min(80).max(700).describe("First sentence answers the question directly."),
  })).min(5).max(8),

  internalLinks: z.strictObject({
    features: z.array(z.strictObject({
      feature: z.string().describe("slug from src/data/app-features.json"),
      anchor: z.string().max(70),
      context: z.string().max(240).describe("One sentence tying the feature to this asset."),
    })).min(3).max(6),
    assets: z.array(z.strictObject({
      ticker: z.string(),
      list: z.enum(assetLists),
      reason: z.string().max(160),
    })).min(3).max(6),
  }),

  sources: z.array(z.strictObject({ title: z.string(), url: https, accessedAt: isoDate })).min(3),

  disclaimer: z.string().min(60),
});

export type AssetList = (typeof assetLists)[number];
export type AssetStats = z.infer<typeof assetStatsSchema>;
export type AssetPage = z.infer<typeof assetPageSchema>;
export type AssetEntity = z.infer<typeof assetEntitySchema>;

/** Zod's issues as "path message" lines, for the scripts' reports and the model's retry. */
export const describeIssues = (error: z.ZodError) =>
  error.issues.map((issue) => `${issue.path.join("/") || "/"} ${issue.message}`);
