// The site's public address, for everything that needs an absolute URL: canonical links, Open Graph, the sitemap,
// robots.txt and JSON-LD. Never the address a page happens to be served from, so preview deployments and localhost
// don't end up as canonical URLs.
//
//   NEXT_PUBLIC_SITE_URL  overrides it (set on Vercel to https://www.cymba.app)
//   VERCEL                set on every Vercel deployment, previews included: they all point at the public address
//
// www.cymba.app is the primary domain; cymba.app redirects to it (308). Not VERCEL_PROJECT_PRODUCTION_URL: Vercel
// picks the shortest domain for it, cymba.app, which would make every canonical URL a redirect.

export const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? (process.env.VERCEL ? "https://www.cymba.app" : "http://localhost:3000"))
  .replace(/\/+$/, "");

// Header, titles, Open Graph, JSON-LD and llms.txt. NEXT_PUBLIC_SITE_NAME overrides it.
export const siteName = process.env.NEXT_PUBLIC_SITE_NAME ?? "Cymba";

/** Whether this build is the one people and crawlers should see. Previews and local builds aren't indexed. */
export const isProduction = process.env.VERCEL_ENV ? process.env.VERCEL_ENV === "production" : process.env.NODE_ENV === "production";

/** "/acoes/petr4" → "https://…/acoes/petr4". */
export const absoluteUrl = (path: string) => `${siteUrl}${path.startsWith("/") ? path : `/${path}`}`;
