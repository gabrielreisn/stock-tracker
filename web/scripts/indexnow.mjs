// Tells Bing (and the other IndexNow engines: Yandex, Seznam, Naver) which pages changed, so they're crawled again
// within hours instead of whenever the sitemap is next read. Google doesn't take part; it reads the sitemap.
// Run it after the deployment is live: the URLs come from the deployed sitemap, and the engines fetch the key file.
//
//   node scripts/indexnow.mjs                      every URL in the sitemap
//   node scripts/indexnow.mjs --since 2026-10-31   only URLs whose lastmod is on or after that day
//   node scripts/indexnow.mjs --dry-run            list them without sending
//
// The key is public by design: public/<key>.txt holds it, and proves the site sent the request.

const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://www.cymba.app").replace(/\/+$/, "");
const key = "9fff00b704cf4ab6c19737d7dae8eb5b";

const args = process.argv.slice(2);
const since = args.includes("--since") ? args[args.indexOf("--since") + 1] : undefined;
const dryRun = args.includes("--dry-run");
if (args.includes("--since") && !/^\d{4}-\d{2}-\d{2}$/.test(since ?? "")) throw new Error("--since takes a day, e.g. 2026-10-31");

const response = await fetch(`${siteUrl}/sitemap.xml`);
if (!response.ok) throw new Error(`${siteUrl}/sitemap.xml: HTTP ${response.status}`);
const entries = [...(await response.text()).matchAll(/<url>([\s\S]*?)<\/url>/g)].map(([, url]) => ({
  loc: url.match(/<loc>(.*?)<\/loc>/)?.[1],
  lastmod: url.match(/<lastmod>(.*?)<\/lastmod>/)?.[1],
}));
// Pages without a lastmod (features, download, methodology) only go out on a full submission.
const urls = entries.filter((e) => e.loc && (!since || (e.lastmod && e.lastmod.slice(0, 10) >= since))).map((e) => e.loc);

console.log(`${urls.length} of ${entries.length} URL(s)${since ? ` changed since ${since}` : ""}.`);
if (dryRun) {
  for (const url of urls) console.log(`  ${url}`);
} else if (urls.length) {
  // One request takes up to 10,000 URLs; the site has a few hundred.
  const result = await fetch("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ host: new URL(siteUrl).host, key, keyLocation: `${siteUrl}/${key}.txt`, urlList: urls }),
  });
  // 200: accepted. 202: accepted, key not checked yet. 403: the key isn't valid (yet: the very first submission for a
  // host got a 403 and the retry a 200). 422: a URL isn't on the host.
  console.log(`IndexNow: HTTP ${result.status} ${result.statusText}`);
  if (!result.ok) process.exitCode = 1;
}
