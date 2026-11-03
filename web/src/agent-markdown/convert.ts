// One page's HTML → Markdown. Keeps the page's <main> (the header, the footer and the navigation are layout), drops
// what isn't text (scripts, styles, SVG, anything marked data-markdown="omit", such as a chart), and reshapes the
// patterns a converter flattens badly. Starts with YAML frontmatter from the page's meta tags (title, description,
// canonical address, image), as Cloudflare's own conversion does.

import { NodeHtmlMarkdown } from "node-html-markdown";
import { HTMLElement, parse } from "node-html-parser";
import type { ConvertOptions } from "./types.ts";

/** What's always left out of the page. */
export const omitted = "script, style, svg, noscript, template, nav, [aria-hidden=true], [data-markdown=omit]";

const converter = new NodeHtmlMarkdown({
  bulletMarker: "-",
  maxConsecutiveNewlines: 2,
  // The default escapes "2022. " anywhere in a sentence, as if it started a numbered list, and "-39%" as if it were a
  // bullet: only what would start a list, a quote or a heading at the start of a line.
  lineStartEscape: [/^(\s*?)((?:[+-]\s)|(?:--)|(?:[=>])|(?:#{1,6}\s))|^(\s*?\d+)(\.\s)/gm, "$1$3\\$2$4"],
});

const yaml = (value: string | undefined) => JSON.stringify(value ?? "");

/**
 * The page's Markdown with YAML frontmatter, and its address (from the canonical link, which names the file). Null for
 * a page that isn't one to publish: no <main>, no canonical link, or noindex (error pages).
 */
export function htmlToMarkdown(html: string, { omit }: ConvertOptions = {}): { url: string; markdown: string } | null {
  const document = parse(html);
  const main = document.querySelector("main");
  const meta = (selector: string, attribute = "content") => document.querySelector(selector)?.getAttribute(attribute);
  const url = meta('link[rel="canonical"]', "href");
  if (!main || !url || /noindex/i.test(meta('meta[name="robots"]') ?? "")) return null;
  const origin = new URL(url).origin;

  for (const node of main.querySelectorAll(omit ? `${omitted}, ${omit}` : omitted)) node.remove();
  // Links within the page (footnote marks like "[3]") become their text.
  for (const a of main.querySelectorAll('a[href^="#"]')) a.replaceWith(` ${a.textContent}`);
  // <details>: the summary becomes a heading over the rest.
  for (const summary of main.querySelectorAll("summary")) summary.replaceWith(`<h3>${summary.innerHTML}</h3>`);
  // Description lists become "**term:** value (more values)".
  for (const dl of main.querySelectorAll("dl")) {
    const items = dl.querySelectorAll("dt").map((dt) => {
      const values: string[] = [];
      for (let dd = dt.nextElementSibling; dd?.tagName === "DD"; dd = dd.nextElementSibling) values.push(dd.innerHTML);
      const [value = "", ...notes] = values;
      return `<li><strong>${dt.innerHTML}:</strong> ${value}${notes.length ? ` (${notes.join(", ")})` : ""}</li>`;
    });
    dl.replaceWith(`<ul>${items.join("")}</ul>`);
  }
  // Cards, a link around a title and a description, become "[title](url): description".
  for (const a of main.querySelectorAll("a")) {
    const blocks = a.childNodes.filter((node): node is HTMLElement => node instanceof HTMLElement && /^(H\d|P|DIV)$/.test(node.tagName));
    if (blocks.length < 2) continue;
    const [title, ...rest] = blocks.map((block) => block.innerHTML);
    a.replaceWith(`<a href="${a.getAttribute("href")}">${title}</a>: ${rest.join(" ")}`);
  }
  // Links side by side (buttons) get a separator.
  for (const a of main.querySelectorAll("a")) {
    const previous = a.previousSibling;
    if (previous instanceof HTMLElement && previous.tagName === "A") a.insertAdjacentHTML("beforebegin", " · ");
  }
  // The Markdown is read away from the site: links get the page's origin.
  for (const a of main.querySelectorAll('a[href^="/"]')) a.setAttribute("href", `${origin}${a.getAttribute("href")}`);

  const image = meta('meta[property="og:image"]');
  const frontmatter = [
    `title: ${yaml(document.querySelector("title")?.textContent)}`,
    `description: ${yaml(meta('meta[name="description"]'))}`,
    `url: ${url}`,
    image && `image: ${image}`,
  ].filter(Boolean);
  return { url, markdown: `---\n${frontmatter.join("\n")}\n---\n\n${converter.translate(main.innerHTML).trim()}\n` };
}
