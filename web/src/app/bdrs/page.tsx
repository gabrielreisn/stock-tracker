import { AssetListPage, assetListMetadata } from "@/components/asset-list-page";

export const metadata = assetListMetadata("bdrs");

export default function BDRsPage() {
  return <AssetListPage list="bdrs" />;
}
