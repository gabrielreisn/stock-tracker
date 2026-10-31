import type { AssetPage } from "@/lib/assets";
import { assetPaths, listNames } from "@/lib/assets";
import { absoluteUrl, siteName, siteUrl } from "@/lib/site";

// Structured data (JSON-LD) for every page, as one @graph whose nodes point at each other by @id. What it's for, and
// what was left out and why: notes/json-ld.md. In short, it tells search engines exactly which company or fund a page
// is about and what it's based on; rich results and AI citations aren't expected from it.

type Node = Record<string, unknown>;

// Releases are published on GitHub; the site links the latest one.
export const downloadUrl = "https://github.com/gabrielreisn/stock-tracker/releases/latest";

const ids = { org: `${siteUrl}/#org`, website: `${siteUrl}/#website`, app: `${siteUrl}/#app` };
const ref = (id: string) => ({ "@id": id });

export const organization: Node = {
  "@type": "Organization",
  "@id": ids.org,
  name: siteName,
  url: `${siteUrl}/`,
};

export const website: Node = {
  "@type": "WebSite",
  "@id": ids.website,
  url: `${siteUrl}/`,
  name: siteName,
  inLanguage: "pt-BR",
  publisher: ref(ids.org),
};

/** The Mac app the site is about: on the home, download and feature pages, not on asset pages. */
export const softwareApplication: Node = {
  "@type": "SoftwareApplication",
  "@id": ids.app,
  name: siteName,
  description: "App de Mac para acompanhar ações da B3 e dos EUA, FIIs, ETFs, renda fixa, fundos e gastos, com Open Finance e assistente de IA.",
  operatingSystem: "macOS 15 ou posterior",
  applicationCategory: "FinanceApplication",
  inLanguage: ["pt-BR", "en"],
  downloadUrl,
  publisher: ref(ids.org),
};

/** A plain text version of Markdown prose: links become their text. */
export const plainText = (text: string) => text.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1").replace(/\*\*?([^*]+)\*\*?/g, "$1");

export function breadcrumb(url: string, items: { name: string; path: string }[]): Node {
  return {
    "@type": "BreadcrumbList",
    "@id": `${url}#breadcrumb`,
    itemListElement: items.map((item, i) => ({ "@type": "ListItem", position: i + 1, name: item.name, item: absoluteUrl(item.path) })),
  };
}

/** A page of the site: its address, title, language, dates and what it's about. */
export function webPage(url: string, fields: Node): Node {
  return {
    "@type": "WebPage",
    "@id": `${url}#page`,
    url,
    inLanguage: "pt-BR",
    isPartOf: ref(ids.website),
    publisher: ref(ids.org),
    ...fields,
  };
}

/** The script tag's content: the graph, with "<" escaped so it can't close the tag. */
export function jsonLd(nodes: Node[]): string {
  return JSON.stringify({ "@context": "https://schema.org", "@graph": nodes }).replace(/</g, "\\u003c");
}

// MARK: - Asset pages

/** The company (Corporation) or fund (InvestmentFund) the page is about, from the records collected for it. */
function assetEntity(page: AssetPage, id: string): Node {
  const e = page.entity;
  const description = plainText(page.summary);
  if (!e) return { "@type": "Thing", "@id": id, name: page.profile.name, description };
  const identifier = [
    e.kind === "InvestmentFund" && { "@type": "PropertyValue", propertyID: "ticker", value: e.ticker },
    e.isin && { "@type": "PropertyValue", propertyID: "ISIN", value: e.isin },
    e.kind === "InvestmentFund" && e.taxId && { "@type": "PropertyValue", propertyID: "CNPJ", value: e.taxId },
  ].filter(Boolean);
  const common = {
    "@id": id,
    name: e.name,
    ...(e.legalName ? { legalName: e.legalName } : {}),
    description,
    ...(identifier.length ? { identifier } : {}),
    ...(e.website ? { url: e.website } : {}),
    ...(e.sameAs.length ? { sameAs: e.sameAs } : {}),
  };
  if (e.kind === "Corporation") {
    return {
      "@type": "Corporation",
      ...common,
      tickerSymbol: e.ticker,
      ...(e.taxId ? { taxID: e.taxId } : {}),
      ...(e.foundingDate ? { foundingDate: e.foundingDate } : {}),
      ...(e.address ? { address: { "@type": "PostalAddress", addressLocality: e.address.locality, addressRegion: e.address.region, addressCountry: e.address.country } } : {}),
    };
  }
  return {
    "@type": "InvestmentFund",
    ...common,
    ...(e.provider ? { provider: { "@type": "Organization", name: e.provider.name, ...(e.provider.url ? { url: e.provider.url } : {}), ...(e.provider.sameAs ? { sameAs: e.provider.sameAs } : {}) } } : {}),
  };
}

/** The computed market figures, as a dataset: how they're measured, over which period, and from which data. */
function assetDataset(page: AssetPage, url: string, entityId: string): Node {
  const { stats } = page;
  const value = (name: string, x: number | null | undefined, unitText = "fração decimal") =>
    x == null ? null : { "@type": "PropertyValue", name, value: x, unitText };
  return {
    "@type": "Dataset",
    "@id": `${url}#dataset`,
    name: `Indicadores de mercado de ${page.ticker}`,
    description: `Rentabilidade total em 1, 3, 5 e 10 anos, volatilidade anualizada, beta contra o ${stats.beta1y.against}, maior queda em 5 anos e proventos dos últimos 12 meses de ${page.ticker}, calculados a partir das cotações diárias ajustadas até ${stats.asOf}.`,
    url: `${url}#volatilidade`,
    about: ref(entityId),
    creator: ref(ids.org),
    inLanguage: "pt-BR",
    dateModified: stats.asOf,
    temporalCoverage: `${stats.historyStarts}/${stats.asOf}`,
    isBasedOn: page.sources[0]?.url,
    measurementTechnique: `Retornos com cotações ajustadas por proventos e desdobramentos; volatilidade: desvio padrão dos retornos logarítmicos diários de 12 meses × √252; beta: covariância dos retornos diários com o ${stats.beta1y.against} sobre a variância do índice, em 12 meses.`,
    variableMeasured: [
      value("Rentabilidade total em 12 meses", stats.returns["1y"]),
      value("Rentabilidade total em 3 anos", stats.returns["3y"]),
      value("Rentabilidade total em 5 anos", stats.returns["5y"]),
      value("Rentabilidade total em 10 anos", stats.returns["10y"]),
      value("Volatilidade anualizada (12 meses)", stats.volatility1y),
      value(`Beta contra o ${stats.beta1y.against} (12 meses)`, stats.beta1y.value, "coeficiente"),
      value("Maior queda em 5 anos", stats.maxDrawdown5y.drawdown),
      value("Dividend yield em 12 meses", stats.dividends?.yield12Months),
    ].filter(Boolean),
  };
}

export function assetJsonLd(page: AssetPage): string {
  const url = absoluteUrl(page.seo.canonicalPath);
  const entityId = `${url}#entity`;
  return jsonLd([
    organization,
    website,
    webPage(url, {
      name: page.seo.title,
      description: page.seo.description,
      datePublished: page.datePublished ?? page.updatedAt,
      dateModified: page.updatedAt,
      breadcrumb: ref(`${url}#breadcrumb`),
      about: ref(entityId),
      mainEntity: ref(entityId),
      // The page's sources, the same ones listed at its end.
      citation: page.sources.map((s) => ({ "@type": "CreativeWork", name: s.title, url: s.url })),
    }),
    assetEntity(page, entityId),
    assetDataset(page, url, entityId),
    breadcrumb(url, [
      { name: listNames[page.list], path: assetPaths[page.list] },
      { name: page.ticker, path: page.seo.canonicalPath },
    ]),
    {
      "@type": "FAQPage",
      "@id": `${url}#faq`,
      isPartOf: ref(`${url}#page`),
      mainEntity: page.faq.map((f) => ({ "@type": "Question", name: f.question, acceptedAnswer: { "@type": "Answer", text: plainText(f.answer) } })),
    },
  ]);
}

/** A list page (hub): the pages it links, in order. */
export function itemList(url: string, items: { name: string; path: string }[]): Node {
  return {
    "@type": "ItemList",
    "@id": `${url}#list`,
    numberOfItems: items.length,
    itemListElement: items.map((item, i) => ({ "@type": "ListItem", position: i + 1, name: item.name, url: absoluteUrl(item.path) })),
  };
}

export { ids as jsonLdIds, ref };
