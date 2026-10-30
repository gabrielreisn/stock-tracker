import type { Metadata } from "next";
import Link from "next/link";
import brStocks from "@/data/assets/br-stocks.json";
import fiis from "@/data/assets/fiis.json";
import usETFs from "@/data/assets/us-etfs.json";
import { assetPaths, assetSlugs, listNames, type AssetList } from "@/lib/assets";
import { date } from "@/lib/format";
import { breadcrumb, itemList, jsonLd, organization, webPage, website } from "@/lib/json-ld";
import { absoluteUrl } from "@/lib/site";

// The list pages (/acoes, /fiis, /etfs): the 100 most traded assets of each kind, ranked as in
// src/data/assets/<list>.json, linking the ones that have a page.

const rankings = { "br-stocks": brStocks, fiis, "us-etfs": usETFs } as const;

const copy: Record<AssetList, { title: string; h1: string; description: string; intro: string }> = {
  "br-stocks": {
    title: "Ações mais negociadas da B3: história, dividendos e volatilidade",
    h1: "Ações brasileiras mais negociadas",
    description: "As 100 ações mais negociadas da B3, com história da empresa, dividendos, volatilidade e fontes oficiais (CVM e B3).",
    intro: "As 100 ações com maior volume financeiro médio diário na B3 nos últimos três meses. Cada página conta a história da empresa, mostra os proventos, a rentabilidade e a volatilidade, e cita as fontes: CVM, B3 e os comunicados da própria companhia.",
  },
  fiis: {
    title: "FIIs mais negociados: estratégia, rendimentos e emissões",
    h1: "Fundos imobiliários mais negociados",
    description: "Os 100 FIIs mais negociados da B3, com estratégia, rendimentos, emissões de cotas e dados oficiais da CVM e do FNET.",
    intro: "Os 100 fundos imobiliários com maior volume financeiro médio diário na B3 nos últimos três meses. Cada página resume a estratégia do fundo a partir do relatório gerencial, os rendimentos, as emissões de cotas e os dados do informe mensal entregue à CVM.",
  },
  "us-etfs": {
    title: "ETFs americanos mais negociados: índice, custos e riscos",
    h1: "ETFs americanos mais negociados",
    description: "Os 100 ETFs mais negociados dos EUA, com o índice que replicam, a emissora, a rentabilidade, a volatilidade e os riscos.",
    intro: "Os 100 ETFs com maior volume financeiro médio diário nas bolsas americanas nos últimos três meses. Cada página explica o que o ETF replica, quem o emite, como ele se comportou e os riscos, inclusive dos ETFs alavancados e inversos.",
  },
};

const compact = (x: number, currency: string) =>
  `${currency === "USD" ? "US$" : "R$"} ${x >= 1e9 ? `${(x / 1e9).toLocaleString("pt-BR", { maximumFractionDigits: 2 })} bi` : `${(x / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} mi`}`;

export function assetListMetadata(list: AssetList): Metadata {
  const { title, description } = copy[list];
  return { title, description, alternates: { canonical: assetPaths[list] }, openGraph: { title, description, url: assetPaths[list], type: "website" } };
}

export async function AssetListPage({ list }: { list: AssetList }) {
  const ranking = rankings[list];
  const withPage = new Set(await assetSlugs(list));
  const path = assetPaths[list];
  const url = absoluteUrl(path);
  const linked = ranking.assets.filter((a) => withPage.has(a.slug)).map((a) => ({ name: `${a.ticker}: ${a.name}`, path: `${path}/${a.slug}` }));

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-10 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([
          organization,
          website,
          webPage(url, { "@type": "CollectionPage", name: copy[list].title, description: copy[list].description, dateModified: ranking.generatedAt, breadcrumb: { "@id": `${url}#breadcrumb` }, mainEntity: { "@id": `${url}#list` } }),
          itemList(url, linked),
          breadcrumb(url, [{ name: listNames[list], path }]),
        ]),
      }} />
      <h1 className="text-4xl font-bold tracking-tight">{copy[list].h1}</h1>
      <p className="mt-4 max-w-3xl text-lg leading-8 text-zinc-700 dark:text-zinc-300">{copy[list].intro}</p>
      <p className="mt-2 text-sm text-zinc-500">
        Ranking de {date(ranking.generatedAt)}: volume financeiro médio diário (preço de fechamento × volume) dos últimos três meses, segundo a Yahoo Finance.
        Veja a <Link href="/metodologia" className="underline underline-offset-2">metodologia</Link>.
      </p>

      <div className="mt-8 overflow-x-auto">
        <table className="w-full text-left text-[0.95rem]">
          <thead className="border-b border-zinc-200 text-sm text-zinc-500 dark:border-zinc-800">
            <tr>
              <th className="py-2 pr-3 font-medium">#</th>
              <th className="py-2 pr-3 font-medium">Ticker</th>
              <th className="py-2 pr-3 font-medium">Nome</th>
              <th className="py-2 text-right font-medium">Volume médio diário</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-100 dark:divide-zinc-900">
            {ranking.assets.map((a) => (
              <tr key={a.ticker}>
                <td className="py-2 pr-3 tabular-nums text-zinc-400">{a.rank}</td>
                <td className="py-2 pr-3 font-semibold">
                  {withPage.has(a.slug)
                    ? <Link href={`${path}/${a.slug}`} className="text-emerald-700 hover:underline dark:text-emerald-400">{a.ticker}</Link>
                    : a.ticker}
                </td>
                <td className="py-2 pr-3 text-zinc-700 dark:text-zinc-300">{a.name}</td>
                <td className="py-2 text-right tabular-nums text-zinc-500">{compact(a.avgDailyValue, a.currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
