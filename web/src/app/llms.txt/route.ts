import catalog from "@/data/app-features.json";
import { allAssetPages } from "@/lib/assets";
import { absoluteUrl, siteName } from "@/lib/site";

// /llms.txt (llmstxt.org): a plain index of the site for language models, with what each page is about. Whether the
// big engines read it is unproven; it costs nothing to serve.

async function llmsText() {
  "use cache";
  const pages = await allAssetPages();
  const section = (title: string, list: string) => [
    `## ${title}`,
    "",
    ...pages.filter((p) => p.list === list).map((p) => `- [${p.title}](${absoluteUrl(p.path)}): ${p.description}`),
    "",
  ];
  return [
    `# ${siteName}`,
    "",
    `> ${siteName}: um app de Mac para acompanhar ações da B3 e dos EUA, FIIs, ETFs, renda fixa, fundos e gastos. O site tem uma página por ativo (os 100 mais negociados de cada tipo), em português, com história, proventos, volatilidade e as fontes de cada dado (CVM, B3, FNET, Wikipedia, Yahoo Finance). As páginas são informativas, não são recomendação de investimento.`,
    "",
    "## Sobre",
    "",
    `- [Metodologia](${absoluteUrl("/metodologia")}): de onde vêm os dados, como os indicadores são calculados e como o texto é escrito e verificado.`,
    `- [Baixar o app](${absoluteUrl("/download")}): requisitos e download do app para Mac.`,
    ...catalog.features.map((f) => `- [${f.name}](${absoluteUrl(f.path)}): ${f.summary}`),
    "",
    ...section("Ações brasileiras", "br-stocks"),
    ...section("Fundos imobiliários (FIIs)", "fiis"),
    ...section("ETFs americanos", "us-etfs"),
    ...section("BDRs (empresas estrangeiras na B3)", "bdrs"),
  ].join("\n");
}

export async function GET() {
  return new Response(await llmsText(), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
