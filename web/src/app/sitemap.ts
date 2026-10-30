import type { MetadataRoute } from "next";
import { cacheLife } from "next/cache";
import catalog from "@/data/app-features.json";
import { allAssetPages, assetPaths } from "@/lib/assets";
import { absoluteUrl } from "@/lib/site";

// /sitemap.xml: the home, the lists, the features, the download and methodology pages, and every asset page with the
// day its content was last generated. Google ignores changefreq and priority, so they're left out.
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  "use cache";
  // The pages change only when they're regenerated and the site is deployed again.
  cacheLife("max");
  const pages = await allAssetPages();
  const latest = pages.map((p) => p.updatedAt).sort().at(-1);
  return [
    { url: absoluteUrl("/"), lastModified: latest },
    ...Object.values(assetPaths).map((path) => ({ url: absoluteUrl(path), lastModified: latest })),
    { url: absoluteUrl("/recursos") },
    ...catalog.features.map((f) => ({ url: absoluteUrl(f.path) })),
    { url: absoluteUrl("/download") },
    { url: absoluteUrl("/metodologia") },
    ...pages.map((p) => ({ url: absoluteUrl(p.path), lastModified: p.updatedAt })),
  ];
}
