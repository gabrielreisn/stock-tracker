// Run after `next build`, in the same build command ("build": "next build && node src/agent-markdown/cli.ts"), so
// the files are in public/ before the deployment is collected. Node runs it by stripping the types.
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
