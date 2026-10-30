import { Suspense } from "react";
import { AssetRoute, assetMetadata, assetStaticParams } from "@/lib/asset-route";

export const generateStaticParams = () => assetStaticParams("fiis");

export const generateMetadata = ({ params }: PageProps<"/fiis/[slug]">) => assetMetadata("fiis", params);

export default function FIIPage({ params }: PageProps<"/fiis/[slug]">) {
  return (
    <Suspense>
      <AssetRoute list="fiis" params={params} />
    </Suspense>
  );
}
