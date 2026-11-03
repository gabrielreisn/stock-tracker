import { absoluteUrl, contentSignal, isProduction } from "@/lib/site";

// /robots.txt. In production every crawler may read the pages, AI answer engines included (GPTBot, ClaudeBot,
// PerplexityBot, Google-Extended…): being quoted by them is the point of the pages. The chart API isn't content.
// Content-Signal (contentsignals.org) says what the content may be used for; Next's robots.ts has no field for it,
// hence a route. Preview and local builds ask crawlers to stay out, so they don't compete with the real site.

function robotsText() {
  if (!isProduction) return "User-agent: *\nDisallow: /\n";
  return [
    "# Content signals (contentsignals.org): search = search results; ai-input = AI answers that quote the pages;",
    "# ai-train = training AI models. yes allows the use, no asks not to.",
    "User-agent: *",
    `Content-Signal: ${contentSignal}`,
    "Allow: /",
    "Disallow: /api/",
    "",
    `Sitemap: ${absoluteUrl("/sitemap.xml")}`,
    "",
  ].join("\n");
}

export function GET() {
  return new Response(robotsText(), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
