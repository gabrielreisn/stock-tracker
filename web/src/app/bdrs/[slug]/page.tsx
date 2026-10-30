import { Suspense } from "react";
import { AssetRoute, assetMetadata, assetStaticParams } from "@/lib/asset-route";

export const generateStaticParams = () => assetStaticParams("bdrs");

export const generateMetadata = ({ params }: PageProps<"/bdrs/[slug]">) => assetMetadata("bdrs", params);

export default function BDRPage({ params }: PageProps<"/bdrs/[slug]">) {
  return (
    <Suspense>
      <AssetRoute list="bdrs" params={params} />
    </Suspense>
  );
}
