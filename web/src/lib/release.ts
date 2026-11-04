import { cacheLife } from "next/cache";
import { downloadUrl } from "@/lib/json-ld";

// The latest release's .dmg, from GitHub's API, so /download/obrigado can start the download itself. A new release
// shows up within the hour without a deploy. If GitHub can't be reached, the page links the release page instead.

export async function latestDmg(): Promise<{ url: string; version: string | null }> {
  "use cache";
  cacheLife("hours");
  try {
    const response = await fetch("https://api.github.com/repos/gabrielreisn/stock-tracker/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(`GitHub: HTTP ${response.status}`);
    const release: { tag_name: string; assets: { name: string; browser_download_url: string }[] } = await response.json();
    const dmg = release.assets.find((a) => a.name.endsWith(".dmg"));
    return dmg ? { url: dmg.browser_download_url, version: release.tag_name.replace(/^v/, "") } : { url: downloadUrl, version: null };
  } catch {
    return { url: downloadUrl, version: null };
  }
}
