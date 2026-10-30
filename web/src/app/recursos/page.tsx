import type { Metadata } from "next";
import Link from "next/link";
import catalog from "@/data/app-features.json";
import { breadcrumb, itemList, jsonLd, organization, softwareApplication, webPage, website } from "@/lib/json-ld";
import { absoluteUrl } from "@/lib/site";

const title = "Recursos do app: carteira, proventos, alertas e mais";
const description = "O que o app faz: carteira consolidada, proventos, comparação com índices, alertas de preço, Open Finance, renda fixa, FGC e assistente de IA.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/recursos" },
  openGraph: { title, description, url: "/recursos", type: "website" },
};

export default function FeaturesPage() {
  const url = absoluteUrl("/recursos");
  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-10 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([
          organization,
          website,
          softwareApplication,
          webPage(url, { "@type": "CollectionPage", name: title, description, about: { "@id": softwareApplication["@id"] }, breadcrumb: { "@id": `${url}#breadcrumb` }, mainEntity: { "@id": `${url}#list` } }),
          itemList(url, catalog.features.map((f) => ({ name: f.name, path: f.path }))),
          breadcrumb(url, [{ name: "Recursos", path: "/recursos" }]),
        ]),
      }} />
      <h1 className="text-4xl font-bold tracking-tight">Recursos do app</h1>
      <p className="mt-4 max-w-3xl text-lg leading-8 text-zinc-700 dark:text-zinc-300">
        Um app de Mac para acompanhar ações da B3 e dos EUA, FIIs, ETFs, renda fixa, fundos e gastos,
        tudo numa só janela e na barra de menus.
      </p>
      <ul className="mt-8 grid gap-4 sm:grid-cols-2">
        {catalog.features.map((f) => (
          <li key={f.slug}>
            <Link href={f.path} className="block h-full rounded-xl border border-zinc-200 p-5 hover:border-zinc-400 dark:border-zinc-800 dark:hover:border-zinc-600">
              <h2 className="font-semibold">{f.name}</h2>
              <p className="mt-1 text-[0.95rem] text-zinc-600 dark:text-zinc-400">{f.summary}</p>
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}
