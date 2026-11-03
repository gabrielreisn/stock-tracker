// After `next build`: every page Next prerendered (<distDir>/server/app/**/*.html) → public/<directory>/<path>.md.
// Next's own pages (_not-found, _global-error) and the shells of dynamic routes ([slug]) are skipped, and so is any
// page without a <main>.

import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { htmlToMarkdown } from "./convert.ts";
import { defaults } from "./index.ts";
import type { BuildOptions } from "./types.ts";

/** "acoes/petr4.html" → "acoes/petr4". */
async function prerenderedPages(directory: string, prefix = ""): Promise<string[]> {
  const found: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith("_") || entry.name.includes("[")) continue;
    const name = `${prefix}${entry.name}`;
    if (entry.isDirectory()) found.push(...(await prerenderedPages(path.join(directory, entry.name), `${name}/`)));
    else if (entry.name.endsWith(".html")) found.push(name.replace(/\.html$/, ""));
  }
  return found;
}

/** Writes the Markdown files, replacing the previous ones. Returns how many were written. */
export async function writeAgentMarkdown({
  root = process.cwd(),
  distDir = ".next",
  publicDir = "public",
  directory = defaults.directory,
  omit,
}: BuildOptions = {}): Promise<number> {
  const appDirectory = path.join(root, distDir, "server/app");
  const outDirectory = path.join(root, publicDir, directory);
  await rm(outDirectory, { recursive: true, force: true });
  let written = 0;
  for (const page of await prerenderedPages(appDirectory)) {
    const markdown = htmlToMarkdown(await readFile(path.join(appDirectory, `${page}.html`), "utf8"), { omit });
    if (!markdown) continue;
    const file = path.join(outDirectory, `${page}.md`);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, markdown);
    written++;
  }
  return written;
}
