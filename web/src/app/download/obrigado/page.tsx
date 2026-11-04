import type { Metadata } from "next";
import Link from "next/link";
import { StartDownload } from "@/components/start-download";
import { latestDmg } from "@/lib/release";

// Where the download button leads: it starts the download and explains the first opening. Each view is a download in
// Web Analytics (the Hobby plan counts page views, not custom events), with the referrer, country and UTM tags of the
// visit. Not indexed and not in the sitemap; without a canonical link it gets no Markdown version either.

export const metadata: Metadata = {
  title: "Baixando o app",
  robots: { index: false, follow: true },
};

export default async function DownloadStartedPage() {
  const dmg = await latestDmg();
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10 sm:px-6">
      <StartDownload url={dmg.url} />
      <h1 className="text-4xl font-bold tracking-tight">Baixando o app</h1>
      <p className="mt-5 text-lg leading-8">
        {dmg.version ? `O download da versão ${dmg.version} começou.` : "O download começa na página da versão mais recente."}{" "}
        Se não começar, <a href={dmg.url} className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">baixe o arquivo .dmg</a>.
      </p>

      <section className="mt-10">
        <h2 className="mb-3 text-2xl font-semibold tracking-tight">Para instalar</h2>
        <ol className="list-decimal space-y-2 pl-5">
          <li>Abra o arquivo .dmg baixado e arraste o app para a pasta <strong>Aplicativos</strong>.</li>
          <li>
            Abra o app pela pasta Aplicativos. Na primeira vez, o macOS avisa que não pôde verificar o app, porque ele ainda
            não é notarizado pela Apple: abra Ajustes do Sistema → Privacidade e Segurança e clique em{" "}
            <strong>Abrir Mesmo Assim</strong>. Isso só é preciso uma vez.
          </li>
          <li>Depois disso, o app se atualiza sozinho quando sai uma versão nova.</li>
        </ol>
      </section>

      <p className="mt-10 text-zinc-600 dark:text-zinc-400">
        Veja <Link href="/recursos" className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">o que o app faz</Link>, ou volte para os{" "}
        <Link href="/acoes" className="font-medium text-emerald-700 hover:underline dark:text-emerald-400">ativos</Link>.
      </p>
    </main>
  );
}
