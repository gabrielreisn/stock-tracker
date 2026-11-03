import type { NextConfig } from "next";
import { withAgentMarkdown } from "./src/agent-markdown";
import { contentSignal } from "./src/lib/site";

const nextConfig: NextConfig = {
  /* config options here */
  cacheComponents: true,
  partialPrefetching: true,
  async rewrites() {
    return {
      beforeFiles: [
        // iOS and some crawlers ask for these at the root; the icon is src/app/apple-icon.png.
        { source: "/apple-touch-icon.png", destination: "/apple-icon.png" },
        { source: "/apple-touch-icon-precomposed.png", destination: "/apple-icon.png" },
        // The Agent Skills Discovery RFC's v0.1.0 path, which some agents still try.
        { source: "/.well-known/skills/index.json", destination: "/.well-known/agent-skills/index.json" },
      ],
    };
  },
  async headers() {
    return [
      // Chrome's private prefetch proxy reads it (public/.well-known/traffic-advice) and needs this type.
      { source: "/.well-known/traffic-advice", headers: [{ key: "Content-Type", value: "application/trafficadvice+json" }] },
      // On the home page, where agents look (RFC 8288): what describes the site for them, the skill that explains how
      // to use it, and the page in Markdown. No api-catalog or service-desc: the site has no public API.
      {
        source: "/",
        headers: [{
          key: "Link",
          value: [
            '</llms.txt>; rel="describedby"; type="text/plain"',
            '</.well-known/ai-catalog.json>; rel="describedby"; type="application/json"',
            '</.well-known/agent-skills/cymba-asset-data/SKILL.md>; rel="service-doc"; type="text/markdown"',
            '</md/index.md>; rel="alternate"; type="text/markdown"',
          ].join(", "),
        }],
      },
    ];
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

// Markdown for Agents (src/agent-markdown): every page's Markdown version, converted from its HTML after the
// build, for requests with `Accept: text/markdown`.
export default withAgentMarkdown(nextConfig, { contentSignal });
