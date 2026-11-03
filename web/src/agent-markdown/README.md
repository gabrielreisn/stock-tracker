# Markdown for Agents

A Markdown version of every prerendered page of a Next.js site, for AI agents (what Cloudflare calls
[Markdown for Agents](https://developers.cloudflare.com/fundamentals/reference/markdown-for-agents/)), without
Cloudflare's proxy. It's self-contained: it imports nothing from the site, so it can become a package later. Browsers
keep getting HTML. A request with `Accept: text/markdown` gets the page's Markdown at the
same address.

- **At build time**, after `next build`, the CLI converts each prerendered page's HTML into `public/md/<path>.md`.
  The page's path comes from its canonical link, since a deployment adapter (Vercel's) stores the HTML under hashed
  names.
- **At request time**, the config wrapper rewrites Markdown requests to those static files. Nothing renders per
  request.

## Usage

```ts
// next.config.ts
import { withAgentMarkdown } from "./src/agent-markdown";

export default withAgentMarkdown(nextConfig, { contentSignal: "search=yes, ai-input=yes, ai-train=no" });
```

```json
// package.json
{ "scripts": { "build": "next build && node src/agent-markdown/cli.ts" } }
```

```ts
// a page's metadata: <link rel="alternate" type="text/markdown" href="/md/blog/post.md">
import { markdownAlternate } from "@/agent-markdown";
export const metadata = { alternates: { canonical: "/blog/post", types: markdownAlternate("/blog/post") } };
```

Add `public/md/` to `.gitignore`. It needs `node-html-markdown` and `node-html-parser` (dev dependencies: they only run at build time).

## What agents get

| Request | Response |
|---|---|
| `GET /blog/post`, `Accept: text/markdown` | `public/md/blog/post.md`, `Content-Type: text/markdown`, `Vary: Accept`, `Content-Signal` |
| `GET /md/blog/post.md` | the same file, plus `X-Robots-Tag: noindex` (search engines keep the HTML page) |
| Paths with a dot (files), `/api/`, `/_next/` | unchanged |

Each file starts with YAML frontmatter (`title`, `description`, `url` from the canonical link, `image` from
`og:image`), followed by the page's `<main>`. The conversion:

- **Leaves out** scripts, styles, SVG, `<nav>`, `aria-hidden` elements and anything marked `data-markdown="omit"`
  (charts, widgets). The `--omit` flag adds more selectors.
- **Rewrites patterns a converter flattens badly:**
  - links within the page become their text;
  - a `<summary>` becomes a heading;
  - a `<dl>` becomes `**term:** value (more values)`;
  - a card (a link wrapping a heading and a description) becomes `[title](url): description`;
  - links side by side get a separator;
  - relative links become absolute.

## CLI

```
node src/agent-markdown/cli.ts [--dir md] [--dist-dir .next] [--public-dir public] [--omit ".ad, .newsletter"]
```

`--dir` must match the `directory` option of `withAgentMarkdown` (both default to `md`).

## Limits

- **Prerendered pages only.** A page rendered per request has no HTML at build time, so it gets no Markdown file.
- **No `x-markdown-tokens` header.** Next's `headers()` are static, so the header can't vary per file.
- **The files must ship.** They're written after `next build`; on Vercel, `public/` is collected after the whole build
  command, so they do. Check other hosts with `curl -sI -H "Accept: text/markdown" https://your.site/`.
- **Pages need a canonical link.** It names the file; pages without one, and noindex pages, are skipped.
