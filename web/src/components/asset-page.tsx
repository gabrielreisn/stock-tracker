import Link from "next/link";
import { Markdown } from "@/components/markdown";
import { PriceChart } from "@/components/price-chart";
import { assetPaths, listNames, type AssetPage } from "@/lib/assets";
import { date, decimal, percent } from "@/lib/format";
import { assetJsonLd } from "@/lib/json-ld";
import features from "@/data/app-features.json";

const featurePath = (slug: string) => features.features.find((f) => f.slug === slug)?.path ?? "/download";

/** What a reference page is, from its address: the links in "Links oficiais". */
function linkLabel(url: string): string {
  const host = new URL(url).hostname;
  if (host === "www.wikidata.org") return "Wikidata";
  if (host.endsWith("wikipedia.org")) return `Wikipédia (${host.split(".")[0]})`;
  if (host.includes("b3.com.br")) return "Página na B3";
  if (host.startsWith("fnet.")) return "Documentos do fundo no FNET (B3)";
  return host.replace(/^www\./, "");
}

function SourceRef({ index }: { index?: number }) {
  if (index == null) return null;
  return <a href={`#fonte-${index}`} className="ml-1 align-super text-[0.65rem] text-zinc-400 hover:text-zinc-600">[{index}]</a>;
}

function Stat({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="rounded-xl border border-zinc-200 p-4 dark:border-zinc-800">
      <div className="text-xs text-zinc-500">{label}</div>
      <div className="mt-1 text-xl font-semibold tabular-nums">{value}</div>
      {note && <div className="mt-0.5 text-xs text-zinc-500">{note}</div>}
    </div>
  );
}

function Section({ id, title, children }: { id?: string; title: string; children: React.ReactNode }) {
  return (
    <section id={id} className="scroll-mt-8">
      <h2 className="mb-4 text-2xl font-semibold tracking-tight">{title}</h2>
      {children}
    </section>
  );
}

export function AssetPageView({ page }: { page: AssetPage }) {
  const { stats } = page;
  const asOf = date(stats.asOf);
  const returns = (["1y", "3y", "5y", "10y"] as const).filter((k) => stats.returns[k] != null);
  const returnLabels = { "1y": "12 meses", "3y": "3 anos", "5y": "5 anos", "10y": "10 anos" };
  // "a PETR4" (a ação), "o SPY" and "o MXRF11" (o fundo).
  const of = page.list === "br-stocks" ? "da" : "do";
  const the = page.list === "br-stocks" ? "a" : "o";
  // Leveraged and inverse ETFs carry their daily target among the characteristics (scripts/asset-sources.mjs).
  const dailyTarget = page.characteristics.find((c) => c.label === "Objetivo diário")?.value;

  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10 text-[1.0625rem] leading-7 text-zinc-800 sm:px-6 dark:text-zinc-200">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: assetJsonLd(page) }} />

      <nav className="mb-6 text-sm text-zinc-500">
        <Link href={assetPaths[page.list]} className="hover:text-zinc-800 dark:hover:text-zinc-200">{listNames[page.list]}</Link>
        <span className="mx-2">›</span>
        <span>{page.ticker}</span>
      </nav>

      <header className="mb-10">
        <p className="mb-2 text-sm font-medium text-emerald-700 dark:text-emerald-400">{page.profile.type}{page.profile.sector ? ` · ${page.profile.sector}` : ""}</p>
        <h1 className="text-4xl font-bold tracking-tight text-zinc-950 dark:text-white">{page.seo.h1}</h1>
        <p className="mt-5 text-lg leading-8">{page.summary}</p>
      </header>

      {dailyTarget && (
        <aside role="note" className="mb-6 rounded-xl border border-amber-300 bg-amber-50 p-4 text-[0.95rem] text-amber-900 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200">
          <strong>ETF alavancado ou inverso.</strong> O {page.ticker} busca {dailyTarget}. Como a meta vale para um único
          dia, em períodos maiores o resultado pode ser muito diferente desse múltiplo, e as perdas podem ser grandes.
        </aside>
      )}

      <div className="mb-4">
        <PriceChart ticker={page.ticker} />
      </div>

      <div className="mb-12 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label={`Beta contra o ${stats.beta1y.against}`} value={decimal(stats.beta1y.value)} note="12 meses" />
        <Stat label="Rentabilidade 12 meses" value={percent(stats.returns["1y"])} note="com proventos" />
        <Stat label="Volatilidade anual" value={percent(stats.volatility1y)} note={stats.volatilityLevel} />
        <Stat label="Dividend yield 12 meses" value={stats.dividends ? percent(stats.dividends.yield12Months) : "—"} />
      </div>

      <div className="space-y-14">
        <Section id="caracteristicas" title={`Características ${of} ${page.ticker}`}>
          <dl className="divide-y divide-zinc-200 rounded-xl border border-zinc-200 text-[0.95rem] dark:divide-zinc-800 dark:border-zinc-800">
            {page.characteristics.map((c) => (
              <div key={c.label} className="grid grid-cols-1 gap-1 px-4 py-3 sm:grid-cols-[14rem_1fr] sm:gap-4">
                <dt className="text-zinc-500">{c.label}</dt>
                <dd className="font-medium">{c.value}<SourceRef index={c.source} /></dd>
              </div>
            ))}
          </dl>
          {page.entity && (page.entity.website || page.entity.sameAs.length > 0 || page.entity.provider?.url) && (
            <p className="mt-4 text-[0.95rem]">
              <span className="text-zinc-500">Links oficiais: </span>
              {[
                page.entity.website && { url: page.entity.website, label: `Site ${page.list === "br-stocks" ? "da empresa" : "do fundo"} (${linkLabel(page.entity.website)})` },
                page.entity.provider?.url && { url: page.entity.provider.url, label: `${page.list === "fiis" ? "Administrador" : "Emissora"}: ${page.entity.provider.name}` },
                ...page.entity.sameAs.map((url) => ({ url, label: linkLabel(url) })),
              ].filter((l): l is { url: string; label: string } => Boolean(l)).map((l, i) => (
                <span key={l.url}>
                  {i > 0 && <span className="text-zinc-400"> · </span>}
                  <a href={l.url} rel="noopener" target="_blank" className="font-medium text-emerald-700 underline decoration-emerald-700/30 underline-offset-2 hover:decoration-emerald-700 dark:text-emerald-400">{l.label}</a>
                </span>
              ))}
            </p>
          )}
        </Section>

        <Section id="historia" title={page.list === "br-stocks" ? `História da ${page.profile.name}` : `História ${of} ${page.ticker}`}>
          <Markdown text={page.history.overview} />
          <ol className="mt-8 space-y-4 border-l-2 border-zinc-200 pl-6 dark:border-zinc-800">
            {page.history.timeline.map((t) => (
              <li key={`${t.date}-${t.event}`} className="relative">
                <span className="absolute top-2 -left-[1.95rem] size-3 rounded-full border-2 border-white bg-emerald-600 dark:border-zinc-950" />
                <div className="text-sm font-semibold tabular-nums text-zinc-500">{date(t.date)}</div>
                <div>{t.event}<SourceRef index={t.source} /></div>
              </li>
            ))}
          </ol>
        </Section>

        {page.sections.map((s) => (
          <Section key={s.id} id={s.id} title={s.heading}>
            <Markdown text={s.body} />
          </Section>
        ))}

        <Section id="volatilidade" title={`Volatilidade ${of} ${page.ticker}`}>
          <Markdown text={page.volatility.explanation} />
          <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {returns.map((k) => <Stat key={k} label={`Rentabilidade ${returnLabels[k]}`} value={percent(stats.returns[k])} />)}
            <Stat label={`Beta contra o ${stats.beta1y.against}`} value={decimal(stats.beta1y.value)} note="12 meses" />
            <Stat label="Maior queda em 5 anos" value={percent(stats.maxDrawdown5y.drawdown)} note={`${date(stats.maxDrawdown5y.from)} a ${date(stats.maxDrawdown5y.to)}`} />
          </div>
          <p className="mt-3 text-sm text-zinc-500">Rentabilidade com proventos reinvestidos, até {asOf}.</p>
        </Section>

        <Section id="perguntas" title="Perguntas frequentes">
          <div className="divide-y divide-zinc-200 border-y border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {page.faq.map((f) => (
              <details key={f.question} className="group py-4">
                <summary className="cursor-pointer list-none font-semibold marker:hidden">
                  <span className="mr-2 inline-block text-zinc-400 transition-transform group-open:rotate-90">›</span>{f.question}
                </summary>
                <Markdown text={f.answer} className="mt-3 pl-5" />
              </details>
            ))}
          </div>
        </Section>

        <section className="rounded-2xl bg-zinc-100 p-6 dark:bg-zinc-900">
          <h2 className="text-xl font-semibold">Acompanhe {the} {page.ticker} no app</h2>
          <p className="mt-1 text-zinc-600 dark:text-zinc-400">O app de Mac para acompanhar ações, FIIs, ETFs, renda fixa e gastos.</p>
          <ul className="mt-4 space-y-3">
            {page.internalLinks.features.map((f) => (
              <li key={f.feature}>
                <Link href={featurePath(f.feature)} className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">{f.anchor}</Link>
                <span className="text-zinc-600 dark:text-zinc-400"> — {f.context}</span>
              </li>
            ))}
          </ul>
          <Link href="/download" className="mt-5 inline-block rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700 dark:bg-white dark:text-zinc-900 dark:hover:bg-zinc-200">Baixar o app</Link>
        </section>

        <Section id="relacionados" title="Ativos relacionados">
          <ul className="grid gap-3 sm:grid-cols-2">
            {page.internalLinks.assets.map((a) => (
              <li key={a.ticker}>
                <Link href={`${assetPaths[a.list]}/${a.ticker.toLowerCase()}`} className="block h-full rounded-xl border border-zinc-200 p-4 hover:border-zinc-400 dark:border-zinc-800 dark:hover:border-zinc-600">
                  <div className="font-semibold">{a.ticker}</div>
                  <div className="mt-1 text-sm text-zinc-500">{a.reason}</div>
                </Link>
              </li>
            ))}
          </ul>
        </Section>

        <Section id="fontes" title="Fontes">
          <ol className="space-y-2 text-sm">
            {page.sources.map((s, i) => (
              <li key={s.url + i} id={`fonte-${i}`} className="scroll-mt-8">
                <span className="mr-2 tabular-nums text-zinc-400">[{i}]</span>
                <a href={s.url} rel="nofollow noopener" target="_blank" className="underline decoration-zinc-300 underline-offset-2 hover:decoration-zinc-600">{s.title}</a>
                <span className="text-zinc-500">, consultado em {date(s.accessedAt)}</span>
              </li>
            ))}
          </ol>
        </Section>

        <footer className="border-t border-zinc-200 pt-6 text-sm text-zinc-500 dark:border-zinc-800">
          <p>{page.disclaimer}</p>
          <p className="mt-2">Atualizado em {date(page.updatedAt)}.</p>
        </footer>
      </div>
    </main>
  );
}
