// The site's public address, for everything that needs an absolute URL: canonical links, Open Graph, the sitemap,
// robots.txt and JSON-LD. Never the address a page happens to be served from, so preview deployments and localhost
// don't end up as canonical URLs.
//
//   NEXT_PUBLIC_SITE_URL           set it once the domain is chosen (e.g. https://example.com)
//   VERCEL_PROJECT_PRODUCTION_URL  Vercel sets it on every deployment, previews included: the production domain

const vercelProduction = process.env.VERCEL_PROJECT_PRODUCTION_URL;

export const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? (vercelProduction ? `https://${vercelProduction}` : "http://localhost:3000"))
  .replace(/\/+$/, "");

// The product's name isn't public yet: a neutral label until it is. Set NEXT_PUBLIC_SITE_NAME to change it everywhere
// (header, Open Graph, JSON-LD, llms.txt).
export const siteName = process.env.NEXT_PUBLIC_SITE_NAME ?? "Investimentos no Mac";

/** Whether this build is the one people and crawlers should see. Previews and local builds aren't indexed. */
export const isProduction = process.env.VERCEL_ENV ? process.env.VERCEL_ENV === "production" : process.env.NODE_ENV === "production";

/** "/acoes/petr4" → "https://…/acoes/petr4". */
export const absoluteUrl = (path: string) => `${siteUrl}${path.startsWith("/") ? path : `/${path}`}`;
