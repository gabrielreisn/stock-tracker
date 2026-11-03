import { agentSkills } from "@/lib/agent-skills";

// /.well-known/agent-skills/index.json: the skills an agent can load to use the site (Agent Skills Discovery RFC
// v0.2.0, github.com/cloudflare/agent-skills-discovery-rfc). Also served at /.well-known/skills/index.json, the v0.1.0
// path (next.config.ts).

export async function GET() {
  const skills = (await agentSkills()).map(({ name, description, url, digest }) => ({ name, type: "skill-md", description, url, digest }));
  return Response.json({ $schema: "https://schemas.agentskills.io/discovery/0.2.0/schema.json", skills });
}
