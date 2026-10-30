// Checks asset pages (src/content/assets/<list>/<slug>.json) against the schema, plus what a schema can't:
// every internal link resolves to a feature or a listed asset, source references exist, the stats belong to the
// ticker, and the text doesn't read as investment advice.
//
//   node scripts/validate-asset-page.mjs src/content/assets/br-stocks/petr4.json [more files…]
//   node scripts/validate-asset-page.mjs            every page
import { readFile, readdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { assetLists, assetPageSchema, describeIssues } from "../src/data/schema/asset-page.ts";

const root = new URL("../", import.meta.url);
const read = async (path) => JSON.parse(await readFile(new URL(path, root), "utf8"));
const { features, site } = await read("src/data/app-features.json");
const lists = Object.fromEntries(await Promise.all(assetLists.map(async (l) => [l, (await read(`src/data/assets/${l}.json`)).assets])));

const featurePaths = new Map(features.map((f) => [f.path, f]));
const assetPaths = new Set(Object.entries(lists).flatMap(([list, assets]) => assets.map((a) => site.assetPaths[list].replace("{slug}", a.slug))));
const otherPaths = new Set([...Object.values(site.hubs), site.download]);
// Wording that turns information into a recommendation (CVM rules on investment analysis): an error, so the page is
// rewritten. "Compre" alone is only a warning: "permite que o investidor compre e venda" describes, not advises.
export const advice = /\b(comprar agora|venda agora|recomendamos|recomendação de compra|recomendad[oa]s? para|indicad[oa]s? para (iniciantes|quem)|vale a pena (comprar|investir)|(é )?um bom investimento|preço-alvo|oportunidade única|não perca|hora de comprar)\b/i;
const mildAdvice = /\bcompre\b/i;

/** Problems (errors) and warnings for one page; `path` is where it is or will be written. */
export function checkPage(page, path) {
  const problems = [], warnings = [];
  const parsed = assetPageSchema.safeParse(page);
  if (!parsed.success) for (const issue of describeIssues(parsed.error)) problems.push(`schema: ${issue}`);
  if (problems.length) return { path, problems, warnings };

  const listed = lists[page.list].find((a) => a.ticker === page.ticker);
  if (!listed) problems.push(`${page.ticker} isn't in src/data/assets/${page.list}.json`);
  if (page.slug !== page.ticker.toLowerCase()) problems.push(`slug should be ${page.ticker.toLowerCase()}`);
  if (!path.endsWith(`${page.list}/${page.slug}.json`)) problems.push(`file should be src/content/assets/${page.list}/${page.slug}.json`);
  if (page.seo.canonicalPath !== site.assetPaths[page.list].replace("{slug}", page.slug)) problems.push(`canonicalPath should be ${site.assetPaths[page.list].replace("{slug}", page.slug)}`);
  if (!page.seo.title.startsWith(page.ticker)) warnings.push("seo.title should start with the ticker");
  if (page.stats.ticker !== page.ticker || page.stats.list !== page.list) problems.push("stats aren't scripts/asset-stats.mjs output for this ticker");
  if (page.volatility.level !== page.stats.volatilityLevel) problems.push(`volatility.level should be ${page.stats.volatilityLevel}, as computed`);

  // Every index into sources must exist.
  const sourceRefs = [...page.characteristics.map((c) => c.source), ...page.history.timeline.map((t) => t.source)].filter((s) => s != null);
  for (const s of sourceRefs) if (s >= page.sources.length) problems.push(`source ${s} doesn't exist (${page.sources.length} sources)`);

  // Links in the prose: internal ones must resolve; count feature links in the text itself.
  const prose = [page.summary, page.volatility.explanation, page.history.overview, ...page.sections.map((s) => s.body), ...page.faq.flatMap((f) => [f.question, f.answer])];
  const featuresInText = new Set();
  for (const text of prose) {
    for (const [, , href] of text.matchAll(/\[([^\]]+)\]\(([^)]+)\)/g)) {
      if (/^https?:/.test(href)) continue;
      const pathOnly = href.split("#")[0];
      if (featurePaths.has(pathOnly)) featuresInText.add(pathOnly);
      else if (!assetPaths.has(pathOnly) && !otherPaths.has(pathOnly)) problems.push(`link to ${href} goes nowhere`);
      if (pathOnly === page.seo.canonicalPath) problems.push("the page links to itself");
    }
    if (advice.test(text)) problems.push(`reads like advice: “${text.match(advice)[0]}”`);
    else if (mildAdvice.test(text)) warnings.push(`may read like advice: “${text.match(mildAdvice)[0]}”`);
  }
  if (featuresInText.size < 3) problems.push(`the text links to ${featuresInText.size} app features (at least 3 different ones)`);

  for (const link of page.internalLinks.features) {
    const feature = features.find((f) => f.slug === link.feature);
    if (!feature) problems.push(`internalLinks: no feature ${link.feature}`);
    else if (!feature.relevantFor.includes(page.list)) warnings.push(`internalLinks: ${link.feature} isn't marked relevant for ${page.list}`);
  }
  for (const link of page.internalLinks.assets) {
    if (!lists[link.list]?.some((a) => a.ticker === link.ticker)) problems.push(`internalLinks: ${link.ticker} isn't in ${link.list}`);
    if (link.ticker === page.ticker) problems.push("internalLinks: the page links to itself");
  }
  return { path, problems: [...new Set(problems)], warnings: [...new Set(warnings)] };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let files = process.argv.slice(2);
  if (!files.length) {
    for (const list of Object.keys(lists)) {
      const dir = new URL(`src/content/assets/${list}/`, root);
      const names = await readdir(dir).catch(() => []);
      files.push(...names.filter((n) => n.endsWith(".json")).map((n) => new URL(n, dir).pathname));
    }
  }
  let failed = 0;
  for (const file of files) {
    const { path, problems, warnings } = checkPage(JSON.parse(await readFile(file, "utf8")), file);
    if (problems.length) failed++;
    console.log(`${problems.length ? "✗" : "✓"} ${path}`);
    for (const p of problems) console.log(`    error: ${p}`);
    for (const w of warnings) console.log(`    warning: ${w}`);
  }
  if (!files.length) console.log("No pages yet in src/content/assets/.");
  process.exit(failed ? 1 : 0);
}
