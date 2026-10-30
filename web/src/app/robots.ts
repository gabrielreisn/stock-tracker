import type { MetadataRoute } from "next";
import { absoluteUrl, isProduction } from "@/lib/site";

// /robots.txt. In production every crawler may read the pages, AI answer engines included (GPTBot, ClaudeBot,
// PerplexityBot, Google-Extended…): being quoted by them is the point of the pages. The chart API isn't content.
// Preview and local builds ask crawlers to stay out, so they don't compete with the real site.
export default function robots(): MetadataRoute.Robots {
  if (!isProduction) return { rules: { userAgent: "*", disallow: "/" } };
  return {
    rules: { userAgent: "*", allow: "/", disallow: "/api/" },
    sitemap: absoluteUrl("/sitemap.xml"),
  };
}
