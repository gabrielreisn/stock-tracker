import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { AssetPageView } from "@/components/asset-page";
import { assetPage, assetSlugs, type AssetList } from "@/lib/assets";
import { siteName } from "@/lib/site";

// What /acoes/[slug], /etfs/[slug] and /fiis/[slug] share: the pages written for their list, prerendered at build time.
// Any other slug is a 404 (with Cache Components, `dynamicParams = false` isn't available: the page calls notFound()).

type Params = Promise<{ slug: string }>;

export async function assetStaticParams(list: AssetList) {
  return (await assetSlugs(list)).map((slug) => ({ slug }));
}

export async function assetMetadata(list: AssetList, params: Params): Promise<Metadata> {
  const page = await assetPage(list, (await params).slug);
  if (!page) return {};
  return {
    title: page.seo.title,
    description: page.seo.description,
    keywords: page.seo.keywords,
    alternates: { canonical: page.seo.canonicalPath },
    openGraph: {
      title: page.seo.title,
      description: page.seo.description,
      url: page.seo.canonicalPath,
      type: "article",
      locale: "pt_BR",
      siteName,
      modifiedTime: page.updatedAt,
    },
  };
}

/** Rendered inside the route's Suspense: params are read there, as Partial Prefetching expects. */
export async function AssetRoute({ list, params }: { list: AssetList; params: Params }) {
  const page = await assetPage(list, (await params).slug);
  if (!page) notFound();
  return <AssetPageView page={page} />;
}
