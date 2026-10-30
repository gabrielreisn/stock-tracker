import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import catalog from "@/data/app-features.json";
import { allAssetPages } from "@/lib/assets";
import { breadcrumb, jsonLd, organization, softwareApplication, webPage, website } from "@/lib/json-ld";
import { absoluteUrl } from "@/lib/site";

// One page per app feature (src/data/app-features.json), the target of the asset pages' internal links. Besides
// what the feature does, it lists the asset pages that link to it, with the sentence each uses.

const findFeature = (slug: string) => catalog.features.find((f) => f.slug === slug);

export const generateStaticParams = () => catalog.features.map((f) => ({ slug: f.slug }));

export async function generateMetadata({ params }: PageProps<"/recursos/[slug]">): Promise<Metadata> {
  const feature = findFeature((await params).slug);
  if (!feature) return {};
  const title = `${feature.name}: recurso do app para Mac`;
  return {
    title,
    description: feature.summary,
    alternates: { canonical: feature.path },
    openGraph: { title, description: feature.summary, url: feature.path, type: "website" },
  };
}

async function Feature({ params }: Pick<PageProps<"/recursos/[slug]">, "params">) {
  const feature = findFeature((await params).slug);
  if (!feature) notFound();
  const url = absoluteUrl(feature.path);
  const mentions = (await allAssetPages())
    .flatMap((page) => page.features.filter((f) => f.slug === feature.slug).map((f) => ({ ...page, context: f.context })))
    .slice(0, 24);

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([
          organization,
          website,
          softwareApplication,
          webPage(url, { name: `${feature.name}: recurso do app para Mac`, description: feature.summary, about: { "@id": softwareApplication["@id"] }, breadcrumb: { "@id": `${url}#breadcrumb` } }),
          breadcrumb(url, [{ name: "Recursos", path: "/recursos" }, { name: feature.name, path: feature.path }]),
        ]),
      }} />
      <nav className="mb-6 text-sm text-zinc-500">
        <Link href="/recursos" className="hover:text-zinc-800 dark:hover:text-zinc-200">Recursos</Link>
        <span className="mx-2">›</span>
        <span>{feature.name}</span>
      </nav>
      <h1 className="text-4xl font-bold tracking-tight">{feature.name}</h1>
      <p className="mt-5 text-lg leading-8">{feature.summary}</p>
      <Link href="/download" className="mt-6 inline-block rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200">
        Baixar o app para Mac
      </Link>

      {mentions.length > 0 && (
        <section className="mt-12">
          <h2 className="mb-4 text-2xl font-semibold tracking-tight">Nos ativos</h2>
          <ul className="space-y-3">
            {mentions.map((m) => (
              <li key={m.path}>
                <Link href={m.path} className="font-semibold text-emerald-700 hover:underline dark:text-emerald-400">{m.ticker}</Link>
                <span className="text-zinc-600 dark:text-zinc-400">: {m.context}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <p className="mt-12 text-sm text-zinc-500">
        <Link href="/recursos" className="underline underline-offset-2">Todos os recursos</Link>
      </p>
    </main>
  );
}

export default function FeaturePage({ params }: PageProps<"/recursos/[slug]">) {
  return (
    <Suspense>
      <Feature params={params} />
    </Suspense>
  );
}
