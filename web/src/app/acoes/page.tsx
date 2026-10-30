import { AssetListPage, assetListMetadata } from "@/components/asset-list-page";

export const metadata = assetListMetadata("br-stocks");

export default function StocksPage() {
  return <AssetListPage list="br-stocks" />;
}
