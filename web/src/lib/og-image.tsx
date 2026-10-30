import { ImageResponse } from "next/og";
import { assetPage, type AssetList } from "@/lib/assets";
import { money, percent } from "@/lib/format";
import { siteName } from "@/lib/site";

// The image shown when a page is shared or cited (Open Graph): the asset's ticker, name, type and two figures, or the
// site's name for the other pages. Generated at build time.

export const ogSize = { width: 1200, height: 630 };

function Card({ eyebrow, title, subtitle, figures }: { eyebrow: string; title: string; subtitle: string; figures: [string, string][] }) {
  return (
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 72, background: "#0a0a0a", color: "#fafafa" }}>
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", justifyContent: "space-between" }}>
          <div style={{ fontSize: 30, color: "#34d399" }}>{eyebrow}</div>
          <div style={{ fontSize: 32, color: "#a1a1aa" }}>{siteName}</div>
        </div>
        <div style={{ fontSize: 112, marginTop: 12, letterSpacing: -2 }}>{title}</div>
        <div style={{ fontSize: 40, color: "#d4d4d8", marginTop: 8 }}>{subtitle}</div>
      </div>
      <div style={{ display: "flex", gap: 72 }}>
        {figures.map(([label, value]) => (
          <div key={label} style={{ display: "flex", flexDirection: "column" }}>
            <div style={{ fontSize: 26, color: "#a1a1aa" }}>{label}</div>
            <div style={{ fontSize: 52 }}>{value}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export async function assetOgImage(list: AssetList, slug: string) {
  const page = await assetPage(list, slug);
  if (!page) return siteOgImage();
  const { stats } = page;
  const name = page.profile.name.length > 48 ? `${page.profile.name.slice(0, 46)}…` : page.profile.name;
  return new ImageResponse(
    <Card
      eyebrow={page.profile.type}
      title={page.ticker}
      subtitle={name}
      figures={[
        [`Preço em ${stats.asOf.split("-").reverse().join("/")}`, money(stats.price, stats.currency)],
        ["Rentabilidade 12 meses", percent(stats.returns["1y"])],
        stats.dividends?.payments12Months
          ? ["Dividend yield 12 meses", percent(stats.dividends.yield12Months)]
          : ["Volatilidade anual", percent(stats.volatility1y)],
      ]}
    />,
    ogSize,
  );
}

export function siteOgImage() {
  return new ImageResponse(
    <Card eyebrow="App de Mac" title={siteName} subtitle="Ações, FIIs, ETFs, renda fixa e gastos num app só" figures={[]} />,
    ogSize,
  );
}
