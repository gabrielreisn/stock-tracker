// After `next build`: every page Next prerendered → public/<directory>/<path>.md. Next stores the HTML under
// <distDir>/server, as app/<path>.html or, with a deployment adapter (Vercel's), as route-cache/<kind>/<hash>/$/….html,
// so the page's path comes from its canonical link, not from the file's name. Pages without one are skipped.

import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { htmlToMarkdown } from "./convert.ts";
import { markdownPath } from "./index.ts";
import type { BuildOptions } from "./types.ts";

async function htmlFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { recursive: true, withFileTypes: true }).catch(() => []);
  return entries.filter((e) => e.isFile() && e.name.endsWith(".html")).map((e) => path.join(e.parentPath, e.name));
}

/** Writes the Markdown files, replacing the previous ones. Returns how many were written. */
export async function writeAgentMarkdown({
  root = process.cwd(),
  distDir = ".next",
  publicDir = "public",
  directory,
  omit,
}: BuildOptions = {}): Promise<number> {
  const pages = new Map<string, string>();
  for (const file of await htmlFiles(path.join(root, distDir, "server"))) {
    const page = htmlToMarkdown(await readFile(file, "utf8"), { omit });
    if (!page) continue;
    const target = markdownPath(new URL(page.url).pathname, { directory });
    // A dynamic route's shell can carry the same address as the page: keep the fuller one.
    if ((pages.get(target)?.length ?? 0) < page.markdown.length) pages.set(target, page.markdown);
  }
  const publicRoot = path.join(root, publicDir);
  await rm(path.join(publicRoot, markdownPath("/", { directory }), ".."), { recursive: true, force: true });
  for (const [target, markdown] of pages) {
    const file = path.join(publicRoot, target);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, markdown);
  }
  return pages.size;
}
