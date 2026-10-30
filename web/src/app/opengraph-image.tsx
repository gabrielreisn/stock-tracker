import { ogSize, siteOgImage } from "@/lib/og-image";
import { siteName } from "@/lib/site";

export const alt = `${siteName}, app de Mac para acompanhar investimentos`;
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return siteOgImage();
}
