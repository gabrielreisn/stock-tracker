import Link from "next/link";
import { siteName } from "@/lib/site";

// The header and footer on every page. Besides navigation, they give crawlers a path from any page to the lists, the
// features, the download and the methodology.

const sections = [
  { href: "/acoes", label: "Ações" },
  { href: "/fiis", label: "FIIs" },
  { href: "/etfs", label: "ETFs" },
  { href: "/recursos", label: "Recursos" },
];

export function SiteHeader() {
  return (
    <header className="border-b border-zinc-200 dark:border-zinc-800">
      <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <Link href="/" className="text-lg font-bold tracking-tight">{siteName}</Link>
        <nav aria-label="Seções" className="flex flex-wrap items-center gap-x-5 gap-y-1 text-sm">
          {sections.map((s) => (
            <Link key={s.href} href={s.href} className="text-zinc-600 hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-white">{s.label}</Link>
          ))}
          <Link href="/download" className="rounded-lg bg-zinc-900 px-3 py-1.5 font-semibold text-white hover:bg-zinc-700 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200">Baixar</Link>
        </nav>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-16 border-t border-zinc-200 dark:border-zinc-800">
      <div className="mx-auto grid w-full max-w-5xl gap-6 px-4 py-8 text-sm text-zinc-500 sm:grid-cols-[1fr_auto] sm:px-6">
        <p className="max-w-xl">
          Um app de Mac para acompanhar investimentos. As páginas de ativos são informativas, não são
          recomendação de investimento, e citam as fontes de cada dado.
        </p>
        <nav aria-label="Rodapé" className="flex flex-wrap gap-x-5 gap-y-1">
          {sections.map((s) => <Link key={s.href} href={s.href} className="hover:text-zinc-800 dark:hover:text-zinc-200">{s.label}</Link>)}
          <Link href="/metodologia" className="hover:text-zinc-800 dark:hover:text-zinc-200">Metodologia</Link>
          <Link href="/download" className="hover:text-zinc-800 dark:hover:text-zinc-200">Baixar</Link>
        </nav>
      </div>
    </footer>
  );
}
