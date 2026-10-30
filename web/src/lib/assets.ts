import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

import { assetPageSchema, type AssetList, type AssetPage } from "@/data/schema/asset-page";

// The asset pages' data, written by scripts/generate-asset-page.mjs (shape: src/data/schema/asset-page.ts).

export type { AssetList, AssetPage };

const contentDirectory = path.join(process.cwd(), "src/content/assets");

/** Slugs of the pages written for a list. */
export async function assetSlugs(list: AssetList): Promise<string[]> {
  const files = await readdir(path.join(contentDirectory, list)).catch(() => []);
  return files.filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, ""));
}

export async function assetPage(list: AssetList, slug: string): Promise<AssetPage | null> {
  "use cache";
  if (!/^[a-z0-9-]+$/.test(slug)) return null;
  const file = await readFile(path.join(contentDirectory, list, `${slug}.json`), "utf8").catch(() => null);
  // Parsed, so a page that doesn't match the schema fails the build instead of rendering half-empty.
  return file ? assetPageSchema.parse(JSON.parse(file)) : null;
}

export const assetPaths: Record<AssetList, string> = { "br-stocks": "/acoes", "us-etfs": "/etfs", fiis: "/fiis" };
export const listNames: Record<AssetList, string> = { "br-stocks": "Ações", "us-etfs": "ETFs", fiis: "FIIs" };
