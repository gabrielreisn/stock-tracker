import type { Metadata } from "next";
import Link from "next/link";
import catalog from "@/data/app-features.json";
import { breadcrumb, downloadUrl, jsonLd, organization, softwareApplication, webPage, website } from "@/lib/json-ld";
import { absoluteUrl } from "@/lib/site";

const title = "Baixar o app para Mac";
const description = "Carteira de ações, FIIs, ETFs, renda fixa e gastos no Mac, com Open Finance, alertas de preço e assistente de IA.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/download" },
  openGraph: { title, description, url: "/download", type: "website" },
};

export default function DownloadPage() {
  const url = absoluteUrl("/download");
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([
          organization,
          website,
          softwareApplication,
          webPage(url, { name: title, description, about: { "@id": softwareApplication["@id"] }, mainEntity: { "@id": softwareApplication["@id"] }, breadcrumb: { "@id": `${url}#breadcrumb` } }),
          breadcrumb(url, [{ name: "Baixar", path: "/download" }]),
        ]),
      }} />
      <h1 className="text-4xl font-bold tracking-tight">{title}</h1>
      <p className="mt-5 text-lg leading-8">{description}</p>

      <a href={downloadUrl} className="mt-8 inline-block rounded-lg bg-zinc-900 px-5 py-3 font-semibold text-white hover:bg-zinc-700 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200">
        Baixar a versão mais recente (.dmg)
      </a>

      <dl className="mt-10 grid gap-x-6 gap-y-3 text-[0.95rem] sm:grid-cols-[12rem_1fr]">
        <dt className="text-zinc-500">Sistema</dt>
        <dd>macOS 15 ou posterior, em Macs com Apple silicon ou Intel</dd>
        <dt className="text-zinc-500">Idiomas</dt>
        <dd>Português e inglês</dd>
      </dl>

      <section className="mt-10">
        <h2 className="mb-3 text-2xl font-semibold tracking-tight">Na primeira abertura</h2>
        <p>
          O app ainda não é notarizado pela Apple. Na primeira vez, o macOS pede confirmação: abra Ajustes do Sistema →
          Privacidade e Segurança e clique em <strong>Abrir Mesmo Assim</strong>. Depois disso, o app se atualiza
          sozinho.
        </p>
      </section>

      <section className="mt-10">
        <h2 className="mb-3 text-2xl font-semibold tracking-tight">O que vem no app</h2>
        <ul className="list-disc space-y-1.5 pl-5">
          {catalog.features.map((f) => (
            <li key={f.slug}><Link href={f.path} className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">{f.name}</Link>: {f.summary}</li>
          ))}
        </ul>
      </section>
    </main>
  );
}
