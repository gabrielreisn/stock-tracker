"use client";

import { useEffect } from "react";
import { markdownPath } from "@/agent-markdown";

// WebMCP (webmachinelearning.github.io/webmcp): tools an AI agent in the browser can call on any page of the site, to
// find an asset's page, read a page as Markdown and get the app. Read-only; they use the Markdown versions of the pages
// (src/agent-markdown). Registered only where the browser has the API: document.modelContext, or
// navigator.modelContext in older Chrome builds.

type Tool = {
  name: string;
  title?: string;
  description: string;
  inputSchema?: object;
  execute: (input: Record<string, unknown>) => Promise<unknown>;
  annotations?: { readOnlyHint?: boolean };
};
type ModelContext = { registerTool(tool: Tool, options?: { signal?: AbortSignal }): Promise<void> };

const lists = [
  { path: "/acoes", kind: "Ação brasileira (B3)" },
  { path: "/fiis", kind: "Fundo imobiliário (FII)" },
  { path: "/bdrs", kind: "BDR" },
  { path: "/etfs", kind: "ETF americano" },
];

const tools = (downloadUrl: string): Tool[] => [
  {
    name: "find_asset",
    title: "Find an asset's page",
    description: "Finds the page about a Brazilian stock, FII, BDR or US ETF by its ticker (e.g. PETR4, MXRF11, AAPL34, SPY), with its history, dividends, returns, volatility and sources, in Portuguese. Returns the page's address and its Markdown address, or found: false.",
    inputSchema: {
      type: "object",
      properties: { ticker: { type: "string", description: "The ticker, e.g. PETR4 or SPY" } },
      required: ["ticker"],
    },
    annotations: { readOnlyHint: true },
    async execute({ ticker }) {
      const slug = String(ticker).trim().toLowerCase().replace(/\.sa$/, "");
      if (!/^[a-z0-9-]+$/.test(slug)) return { found: false };
      for (const list of lists) {
        const path = `${list.path}/${slug}`;
        const response = await fetch(markdownPath(path), { method: "HEAD" });
        if (response.ok) return { found: true, kind: list.kind, url: new URL(path, location.origin).href, markdown: new URL(markdownPath(path), location.origin).href };
      }
      return { found: false, lists: lists.map((l) => new URL(l.path, location.origin).href) };
    },
  },
  {
    name: "read_page",
    title: "Read a page as Markdown",
    description: "Returns a page of this site as Markdown: the current page if no path is given, or e.g. /acoes/petr4, /fiis (the ranking of the 100 most traded FIIs), /metodologia or /download. Figures are as of the date the page states; the pages are not investment advice.",
    inputSchema: {
      type: "object",
      properties: { path: { type: "string", description: "A path on this site, starting with /" } },
    },
    annotations: { readOnlyHint: true },
    async execute({ path }) {
      const target = typeof path === "string" && path.startsWith("/") ? path : location.pathname;
      const response = await fetch(markdownPath(target));
      if (!response.ok) return { found: false, path: target };
      return { found: true, url: new URL(target, location.origin).href, markdown: await response.text() };
    },
  },
  {
    name: "get_app",
    title: "Get the Cymba app",
    description: "Cymba, the free Mac app this site is about: tracks B3 and US stocks, FIIs, ETFs, fixed income, funds and spending (Open Finance) in one window. Returns the download link, the requirements and the feature pages.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
    async execute() {
      return {
        name: "Cymba",
        requirements: "macOS 15 or later, Apple silicon or Intel; Portuguese and English",
        download: downloadUrl,
        page: new URL("/download", location.origin).href,
        features: new URL("/recursos", location.origin).href,
      };
    },
  },
];

/** `downloadUrl`: the latest release, from the server (lib/json-ld.ts reads files, so it can't be bundled here). */
export function WebMcp({ downloadUrl }: { downloadUrl: string }) {
  useEffect(() => {
    const context = (document as { modelContext?: ModelContext }).modelContext
      ?? (navigator as { modelContext?: ModelContext }).modelContext;
    if (!context) return;
    const controller = new AbortController();
    // A failed registration (an older API shape, a name already taken) leaves the page as it is.
    for (const tool of tools(downloadUrl)) {
      Promise.resolve().then(() => context.registerTool(tool, { signal: controller.signal })).catch(() => {});
    }
    return () => controller.abort();
  }, [downloadUrl]);
  return null;
}
