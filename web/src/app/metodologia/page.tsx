import type { Metadata } from "next";
import Link from "next/link";
import { breadcrumb, jsonLd, organization, webPage, website } from "@/lib/json-ld";
import { absoluteUrl } from "@/lib/site";

// How the asset pages are made: the selection, the sources, the computed figures, how the text is written and checked,
// and the limits. A trust signal for readers, and something search and answer engines can quote.

const title = "Metodologia: como as páginas de ativos são feitas";
const description = "De onde vêm os dados das páginas de ações, FIIs e ETFs, como os indicadores são calculados e como o texto é escrito e verificado.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/metodologia" },
  openGraph: { title, description, url: "/metodologia", type: "article" },
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-10">
      <h2 className="mb-3 text-2xl font-semibold tracking-tight">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

export default function MethodologyPage() {
  const url = absoluteUrl("/metodologia");
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10 text-[1.0625rem] leading-7 sm:px-6">
      <script type="application/ld+json" dangerouslySetInnerHTML={{
        __html: jsonLd([organization, website, webPage(url, { name: title, description, breadcrumb: { "@id": `${url}#breadcrumb` } }), breadcrumb(url, [{ name: "Metodologia", path: "/metodologia" }])]),
      }} />
      <h1 className="text-4xl font-bold tracking-tight">{title}</h1>
      <p className="mt-5 text-lg leading-8">
        As páginas de <Link href="/acoes" className="underline underline-offset-2">ações</Link>,{" "}
        <Link href="/fiis" className="underline underline-offset-2">FIIs</Link>,{" "}
        <Link href="/etfs" className="underline underline-offset-2">ETFs</Link> e{" "}
        <Link href="/bdrs" className="underline underline-offset-2">BDRs</Link> deste site são informativas: contam a
        história de cada ativo, mostram seus números e citam de onde cada dado veio. Não são recomendação de investimento.
      </p>

      <Section title="Quais ativos têm página">
        <p>
          Os 100 ativos de cada tipo com maior volume financeiro médio diário (preço de fechamento × volume) nos últimos
          três meses, a partir das cotações diárias da Yahoo Finance. Os candidatos vêm dos índices da B3 (IBrA para
          ações, IFIX para FIIs, BDRX para BDRs), das listas de FIIs da CVM e de BDRs da B3, e dos ETFs mais ativos nos EUA.
          BDRs de ETFs ficam de fora: os ETFs têm a sua própria lista.
        </p>
      </Section>

      <Section title="De onde vêm os dados">
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>B3:</strong> cadastro da companhia listada, setor, segmento de listagem e códigos de negociação.</li>
          <li><strong>CVM:</strong> cadastro de companhias abertas, fatos relevantes e o informe mensal dos FIIs (patrimônio, cotistas, administrador).</li>
          <li><strong>FNET (B3):</strong> relatórios gerenciais, fatos relevantes e ofertas de cotas dos FIIs.</li>
          <li><strong>Wikidata e Wikipedia:</strong> história, fundação e contexto; para ETFs, também o índice e a emissora; para BDRs, a empresa e a ação original.</li>
          <li><strong>Yahoo Finance:</strong> cotações diárias, proventos e o gráfico de preço.</li>
        </ul>
        <p>Cada página lista as suas fontes, com link e data de consulta, e os dados da tabela de características indicam a fonte de cada valor.</p>
      </Section>

      <Section title="Como os indicadores são calculados">
        <ul className="list-disc space-y-1.5 pl-5">
          <li><strong>Rentabilidade total</strong> (12 meses, 3, 5 e 10 anos): com cotações ajustadas por proventos e desdobramentos.</li>
          <li><strong>Volatilidade anualizada:</strong> desvio padrão dos retornos logarítmicos diários dos últimos 12 meses × √252. Abaixo de 15% é baixa; até 25%, moderada; até 40%, alta; acima, muito alta.</li>
          <li><strong>Beta:</strong> sensibilidade aos movimentos do Ibovespa (ações e FIIs) ou do S&P 500 (ETFs e BDRs), nos últimos 12 meses. A rentabilidade dos BDRs é em reais e inclui a variação do câmbio.</li>
          <li><strong>Maior queda:</strong> a maior perda do pico ao vale nos últimos 5 anos, com as datas.</li>
          <li><strong>Proventos e dividend yield:</strong> soma dos proventos pagos nos últimos 12 meses, dividida pelo preço atual.</li>
        </ul>
        <p>As cotações do gráfico têm atraso de cerca de 15 minutos na B3.</p>
      </Section>

      <Section title="Como o texto é escrito e verificado">
        <p>
          O texto é escrito por um modelo de linguagem aberto, rodando localmente, a partir apenas das fontes coletadas
          para aquele ativo. A tabela de características, os números e as fontes são preenchidos por código, não pelo
          modelo. Antes de uma página ser publicada, verificações automáticas:
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>removem frases com números que não estão nas fontes;</li>
          <li>conferem que cada data da linha do tempo aparece na fonte citada, com a mesma precisão;</li>
          <li>rejeitam linguagem de recomendação (&quot;compre&quot;, &quot;bom investimento&quot;, &quot;preço-alvo&quot;);</li>
          <li>conferem que todos os links internos existem.</li>
        </ul>
        <p>Uma página que não passa nessas verificações não é publicada.</p>
      </Section>

      <Section title="Limites">
        <p>
          Modelos de linguagem podem errar, e a Wikipedia é uma fonte secundária. Fatos importantes devem ser conferidos
          nas fontes primárias citadas em cada página (CVM, B3, documentos do fundo). Rentabilidade passada não garante
          rentabilidade futura.
        </p>
      </Section>
    </main>
  );
}
