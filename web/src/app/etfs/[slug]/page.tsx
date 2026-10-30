import { Suspense } from "react";
import { AssetRoute, assetMetadata, assetStaticParams } from "@/lib/asset-route";

export const generateStaticParams = () => assetStaticParams("us-etfs");

export const generateMetadata = ({ params }: PageProps<"/etfs/[slug]">) => assetMetadata("us-etfs", params);

export default function ETFPage({ params }: PageProps<"/etfs/[slug]">) {
  return (
    <Suspense>
      <AssetRoute list="us-etfs" params={params} />
    </Suspense>
  );
}
