import type { Metadata } from "next";
import Link from "next/link";
import catalog from "@/data/app-features.json";
import brStocks from "@/data/assets/br-stocks.json";
import fiis from "@/data/assets/fiis.json";
import usETFs from "@/data/assets/us-etfs.json";
import { assetPaths, assetSlugs, listNames, type AssetList } from "@/lib/assets";
import { jsonLd, organization, softwareApplication, webPage, website } from "@/lib/json-ld";
import { siteUrl } from "@/lib/site";

const title = "Sua carteira de investimentos no Mac";
const description = "App de Mac para acompanhar ações da B3 e dos EUA, FIIs, ETFs, renda fixa e gastos, com Open Finance, alertas de preço e assistente de IA.";

export const metadata: Metadata = {
  title: { absolute: title },
  description,
  alternates: { canonical: "/" },
  openGraph: { title, description, url: "/", type: "website" },
};

const rankings: Record<AssetList, typeof brStocks> = { "br-stocks": brStocks, fiis, "us-etfs": usETFs };

export default async function Home() {
  const lists = await Promise.all((["br-stocks", "fiis", "us-etfs"] as const).map(async (list) => {
    const withPage = new Set(await assetSlugs(list));
    return { list, assets: rankings[list].assets.filter((a) => withPage.has(a.slug)).slice(0, 10) };
  }));

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-12 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([organization, website, softwareApplication, webPage(`${siteUrl}/`, { name: title, description, about: { "@id": softwareApplication["@id"] } })]),
      }} />

      <section className="max-w-3xl">
        <h1 className="text-5xl font-bold tracking-tight">Sua carteira inteira, no Mac</h1>
        <p className="mt-5 text-xl leading-8 text-zinc-700 dark:text-zinc-300">
          Um app que reúne ações da B3 e dos EUA, FIIs, ETFs, renda fixa, fundos e gastos numa janela só, e na barra
          de menus.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/download" className="rounded-lg bg-zinc-900 px-5 py-3 font-semibold text-white hover:bg-zinc-700 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200">Baixar para Mac</Link>
          <Link href="/recursos" className="rounded-lg border border-zinc-300 px-5 py-3 font-semibold hover:border-zinc-500 dark:border-zinc-700">Ver recursos</Link>
        </div>
      </section>

      <section className="mt-16">
        <h2 className="text-2xl font-semibold tracking-tight">O que o app faz</h2>
        <ul className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {catalog.features.slice(0, 9).map((f) => (
            <li key={f.slug}>
              <Link href={f.path} className="block h-full rounded-xl border border-zinc-200 p-5 hover:border-zinc-400 dark:border-zinc-800 dark:hover:border-zinc-600">
                <h3 className="font-semibold">{f.name}</h3>
                <p className="mt-1 text-[0.95rem] text-zinc-600 dark:text-zinc-400">{f.summary}</p>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section className="mt-16">
        <h2 className="text-2xl font-semibold tracking-tight">Os ativos mais negociados</h2>
        <p className="mt-2 max-w-3xl text-zinc-600 dark:text-zinc-400">
          História, proventos, volatilidade e fontes oficiais de cada ativo. Veja como as páginas são feitas na{" "}
          <Link href="/metodologia" className="underline underline-offset-2">metodologia</Link>.
        </p>
        <div className="mt-6 grid gap-8 sm:grid-cols-3">
          {lists.map(({ list, assets }) => (
            <div key={list}>
              <h3 className="font-semibold"><Link href={assetPaths[list]} className="hover:underline">{listNames[list]}</Link></h3>
              <ul className="mt-3 space-y-1.5 text-[0.95rem]">
                {assets.map((a) => (
                  <li key={a.ticker}>
                    <Link href={`${assetPaths[list]}/${a.slug}`} className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">{a.ticker}</Link>
                    <span className="text-zinc-500"> {a.name}</span>
                  </li>
                ))}
              </ul>
              <Link href={assetPaths[list]} className="mt-3 inline-block text-sm underline underline-offset-2">{list === "br-stocks" ? "Todas as ações" : `Todos os ${listNames[list]}`}</Link>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
