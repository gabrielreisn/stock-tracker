import { Suspense } from "react";
import { AssetRoute, assetMetadata, assetStaticParams } from "@/lib/asset-route";

export const generateStaticParams = () => assetStaticParams("br-stocks");

export const generateMetadata = ({ params }: PageProps<"/acoes/[slug]">) => assetMetadata("br-stocks", params);

export default function StockPage({ params }: PageProps<"/acoes/[slug]">) {
  return (
    <Suspense>
      <AssetRoute list="br-stocks" params={params} />
    </Suspense>
  );
}
