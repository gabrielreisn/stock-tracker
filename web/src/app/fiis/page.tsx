import { AssetListPage, assetListMetadata } from "@/components/asset-list-page";

export const metadata = assetListMetadata("fiis");

export default function FIIsPage() {
  return <AssetListPage list="fiis" />;
}
