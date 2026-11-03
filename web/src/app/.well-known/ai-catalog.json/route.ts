import { agentSkills } from "@/lib/agent-skills";
import { siteName, siteUrl } from "@/lib/site";

// /.well-known/ai-catalog.json: one manifest of what agents can use on the site (Agentic Resource Discovery, an
// ai-catalog: agenticresourcediscovery.org, ai-catalog.io). Today the agent skills; an MCP server card would go here
// too. Readable from any origin, as ARD asks.

export async function GET() {
  const host = new URL(siteUrl).host;
  const entries = (await agentSkills()).map((skill) => ({
    identifier: `urn:air:${host}:skill:${skill.name}`,
    displayName: skill.title,
    description: skill.description,
    type: "application/agent-skills+md",
    url: skill.url,
    digest: skill.digest,
    representativeQueries: skill.queries,
  }));
  return Response.json(
    { specVersion: "1.0", host: { displayName: siteName, identifier: host, documentationUrl: `${siteUrl}/llms.txt` }, entries },
    { headers: { "Access-Control-Allow-Origin": "*" } },
  );
}
