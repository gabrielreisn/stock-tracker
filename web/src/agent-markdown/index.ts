// Markdown for Agents (Cloudflare's name for it): a Markdown version of every prerendered page of a Next.js site, for AI
// agents. Self-contained, so it can become a package. After `next build`, cli.ts converts each page's HTML
// into public/<directory>/<path>.md; withAgentMarkdown() serves those files to requests that ask for Markdown
// (`Accept: text/markdown`), at the page's own address, with the headers agents look for.
//
// This file only touches the Next config and paths: the conversion (and its HTML parser) is in convert.ts and build.ts.

import type { NextConfig } from "next";
import type { AgentMarkdownOptions } from "./types.ts";

export const defaults = { directory: "md" };

/** "/acoes/petr4" → "/md/acoes/petr4.md", "/" → "/md/index.md". */
export function markdownPath(path: string, { directory = defaults.directory }: Pick<AgentMarkdownOptions, "directory"> = {}) {
  const clean = path.replace(/\/+$/, "");
  return `/${directory}${clean === "" ? "/index" : clean}.md`;
}

/** For a page's `alternates.types` metadata: <link rel="alternate" type="text/markdown"> to its Markdown version. */
export const markdownAlternate = (path: string, options?: Pick<AgentMarkdownOptions, "directory">) => ({
  "text/markdown": markdownPath(path, options),
});

/**
 * Wraps a Next config so that:
 * - a page requested with `Accept: text/markdown` is rewritten to its Markdown file, before Next's own routes;
 * - those responses carry `Content-Type: text/markdown`, `Vary: Accept` and, if given, `Content-Signal`;
 * - the Markdown files at /<directory>/… are `noindex`, so search engines keep the HTML page.
 * Paths with a dot (files), /api/, /_next/ and /<directory>/ itself are left alone.
 */
export function withAgentMarkdown(nextConfig: NextConfig = {}, options: AgentMarkdownOptions = {}): NextConfig {
  const { directory = defaults.directory, contentSignal } = options;
  const pages = `/:path((?!api/|_next/|${directory}/)[^.]+)`;
  const has = [{ type: "header" as const, key: "accept", value: ".*text/markdown.*" }];
  const markdown = [
    { key: "Content-Type", value: "text/markdown; charset=utf-8" },
    ...(contentSignal ? [{ key: "Content-Signal", value: contentSignal }] : []),
  ];
  const negotiated = [...markdown, { key: "Vary", value: "Accept" }];

  return {
    ...nextConfig,
    async rewrites() {
      const own = [
        { source: "/", has, destination: `/${directory}/index.md` },
        { source: pages, has, destination: `/${directory}/:path.md` },
      ];
      const theirs = (await nextConfig.rewrites?.()) ?? [];
      // A plain array of rewrites means afterFiles.
      if (Array.isArray(theirs)) return { beforeFiles: own, afterFiles: theirs, fallback: [] };
      return { ...theirs, beforeFiles: [...own, ...(theirs.beforeFiles ?? [])] };
    },
    async headers() {
      return [
        ...((await nextConfig.headers?.()) ?? []),
        { source: "/", has, headers: negotiated },
        { source: pages, has, headers: negotiated },
        { source: `/${directory}/:path*`, headers: [...markdown, { key: "X-Robots-Tag", value: "noindex" }] },
      ];
    },
  };
}
