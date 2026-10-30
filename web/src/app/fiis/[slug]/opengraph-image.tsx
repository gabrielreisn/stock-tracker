import { assetSlugs } from "@/lib/assets";
import { assetOgImage, ogSize } from "@/lib/og-image";

export const alt = "Resumo do ativo: tipo, preço, rentabilidade e volatilidade";
export const size = ogSize;
export const contentType = "image/png";

export const generateStaticParams = async () => (await assetSlugs("fiis")).map((slug) => ({ slug }));

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  return assetOgImage("fiis", (await params).slug);
}
