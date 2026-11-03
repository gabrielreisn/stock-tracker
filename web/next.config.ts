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
    // Chrome's private prefetch proxy reads it (public/.well-known/traffic-advice) and needs this type.
    return [{ source: "/.well-known/traffic-advice", headers: [{ key: "Content-Type", value: "application/trafficadvice+json" }] }];
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
