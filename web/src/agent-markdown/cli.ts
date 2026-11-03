// Converts the pages of the last `next build` into public/<directory>. Deployment adapters (Vercel's) collect public/
// during `next build`, so a second build has to follow for the files to ship:
// "build": "next build && node src/agent-markdown/cli.ts && next build". Node runs this file by stripping the types.
//
//   node src/agent-markdown/cli.ts [--dir md] [--dist-dir .next] [--public-dir public] [--omit ".ad, .newsletter"]

import { writeAgentMarkdown } from "./build.ts";

const args = process.argv.slice(2);
const flag = (name: string) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);

const written = await writeAgentMarkdown({
  directory: flag("--dir"),
  distDir: flag("--dist-dir"),
  publicDir: flag("--public-dir"),
  omit: flag("--omit"),
});
console.log(`Markdown for Agents: ${written} page(s) in ${flag("--public-dir") ?? "public"}/${flag("--dir") ?? "md"}.`);
