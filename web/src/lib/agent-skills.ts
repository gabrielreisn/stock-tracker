import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { absoluteUrl } from "@/lib/site";

// The site's agent skills: SKILL.md files in public/.well-known/agent-skills/<name>/, listed with their SHA-256 in
// /.well-known/agent-skills/index.json (Agent Skills Discovery RFC v0.2.0) and in /.well-known/ai-catalog.json (ARD).
// The description (frontmatter) and the title (first heading) come from each file, so the lists can't drift from it.

/** The skills, with the questions they answer (for the AI catalog's representativeQueries: 2–5 each). */
const skills = [
  {
    name: "cymba-asset-data",
    queries: [
      "PETR4 paga dividendos?",
      "qual a volatilidade do MXRF11",
      "como o SPY se comportou nos últimos 5 anos",
      "app para acompanhar carteira de ações no Mac",
    ],
  },
];

export async function agentSkills() {
  "use cache";
  return Promise.all(skills.map(async ({ name, queries }) => {
    const urlPath = `/.well-known/agent-skills/${name}/SKILL.md`;
    const file = await readFile(path.join(process.cwd(), "public", urlPath));
    const text = file.toString("utf8");
    const description = text.match(/^description:\s*(.+)$/m)?.[1].trim() ?? "";
    const title = text.match(/^# (.+)$/m)?.[1].trim() ?? name;
    return { name, title, description, queries, url: absoluteUrl(urlPath), digest: `sha256:${createHash("sha256").update(file).digest("hex")}` };
  }));
}
