// Adds what the records say about each asset to pages already written, without the model: the entity for JSON-LD
// (company or fund, ticker, ISIN, CNPJ, founding date, address, official site, Wikidata and Wikipedia) and the date
// the page was first published. The prose, characteristics and sources stay as they are, so source references in the
// text keep pointing at the same sources. Pages generated from now on get the same fields from the generator.
//
//   node scripts/enrich-asset-pages.mjs              every page
//   node scripts/enrich-asset-pages.mjs PETR4 SPY    some pages
import { readFile, readdir, writeFile } from "node:fs/promises";
import { collectSources, findAsset, lists, root } from "./asset-sources.mjs";
import { checkPage } from "./validate-asset-page.mjs";

// The page's keys in the schema's order, so the JSON reads the same as a generated page.
const order = ["ticker", "slug", "list", "locale", "updatedAt", "datePublished", "seo", "summary", "entity", "profile", "characteristics",
  "stats", "volatility", "history", "sections", "faq", "internalLinks", "sources", "disclaimer"];

const wanted = process.argv.slice(2).map((t) => t.toUpperCase());
const pages = [];
for (const list of Object.keys(lists)) {
  for (const name of await readdir(new URL(`src/content/assets/${list}/`, root)).catch(() => [])) {
    const asset = name.endsWith(".json") && findAsset(name.replace(/\.json$/, ""));
    if (asset && (!wanted.length || wanted.includes(asset.ticker))) pages.push(asset);
  }
}

let updated = 0;
const failed = [];
for (const asset of pages) {
  const path = `src/content/assets/${asset.list}/${asset.slug}.json`;
  try {
    const page = JSON.parse(await readFile(new URL(path, root), "utf8"));
    const dossier = await collectSources(asset);
    // undefined fields dropped, as they would be in a written file.
    if (dossier.entity) page.entity = JSON.parse(JSON.stringify(dossier.entity));
    page.datePublished ??= page.updatedAt;
    const ordered = Object.fromEntries(order.filter((k) => k in page).map((k) => [k, page[k]]));
    const { problems } = checkPage(ordered, path);
    if (problems.length) throw new Error(problems.join("; "));
    await writeFile(new URL(path, root), JSON.stringify(ordered, null, 2) + "\n");
    updated++;
    console.log(`✓ ${asset.ticker}: ${dossier.entity ? `${dossier.entity.sameAs.length} links, ${dossier.entity.website ? "site" : "no site"}` : "no entity"}${dossier.missing.length ? ` (missing: ${dossier.missing.join("; ")})` : ""}`);
  } catch (error) {
    failed.push(asset.ticker);
    console.log(`✗ ${asset.ticker}: ${error.message}`);
  }
}
console.log(`\n${updated} updated${failed.length ? `, ${failed.length} failed: ${failed.join(", ")}` : ""}.`);
process.exit(failed.length ? 1 : 0);
