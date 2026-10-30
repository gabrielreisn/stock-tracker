import Link from "next/link";
import type { ReactNode } from "react";

// The small Markdown subset the asset pages use: paragraphs, "- " lists, **bold**, *italics* and links. Internal links
// go through next/link; anything else on the page is plain text.

function inline(text: string, key: string): ReactNode[] {
  const parts: ReactNode[] = [];
  const pattern = /\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*|\*([^*]+)\*/g;
  let last = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > last) parts.push(text.slice(last, match.index));
    const id = `${key}-${match.index}`;
    if (match[1]) {
      parts.push(match[2].startsWith("/")
        ? <Link key={id} href={match[2]} className="font-medium text-emerald-700 underline decoration-emerald-700/30 underline-offset-2 hover:decoration-emerald-700 dark:text-emerald-400">{match[1]}</Link>
        : match[1]);
    } else if (match[3]) {
      parts.push(<strong key={id}>{match[3]}</strong>);
    } else {
      parts.push(<em key={id}>{match[4]}</em>);
    }
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

export function Markdown({ text, className = "" }: { text: string; className?: string }) {
  const blocks = text.trim().split(/\n\s*\n/);
  return (
    <div className={`space-y-4 ${className}`}>
      {blocks.map((block, i) => {
        const lines = block.split("\n").map((l) => l.trim()).filter(Boolean);
        const items = lines.filter((l) => /^[-*] /.test(l));
        if (items.length && items.length === lines.length) {
          return (
            <ul key={i} className="list-disc space-y-1.5 pl-5">
              {items.map((item, j) => <li key={j}>{inline(item.slice(2), `${i}-${j}`)}</li>)}
            </ul>
          );
        }
        if (items.length) {
          // A sentence introducing a list, in the same block.
          const intro = lines.filter((l) => !/^[-*] /.test(l)).join(" ");
          return (
            <div key={i} className="space-y-2">
              <p>{inline(intro, `${i}`)}</p>
              <ul className="list-disc space-y-1.5 pl-5">
                {items.map((item, j) => <li key={j}>{inline(item.slice(2), `${i}-${j}`)}</li>)}
              </ul>
            </div>
          );
        }
        return <p key={i}>{inline(lines.join(" "), `${i}`)}</p>;
      })}
    </div>
  );
}
