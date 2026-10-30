import { AssetListPage, assetListMetadata } from "@/components/asset-list-page";

export const metadata = assetListMetadata("us-etfs");

export default function ETFsPage() {
  return <AssetListPage list="us-etfs" />;
}
