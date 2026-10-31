import { ImageResponse } from "next/og";
import { assetPage, type AssetList } from "@/lib/assets";
import { money, percent } from "@/lib/format";
import { siteName } from "@/lib/site";

// The image shown when a page is shared or cited (Open Graph): the asset's ticker, name, type and two figures, or the
// site's name for the other pages. Generated at build time.

export const ogSize = { width: 1200, height: 630 };

/** The site's icon, a copy of src/app/icon.svg: change both together. */
function Mark({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="4.5 4 55 55">
      <defs>
        <clipPath id="sail"><path d="M19 14H45Q49.5 25 42.5 37.5Q32 34.2 21.5 37.5Q14.5 25 19 14z" /></clipPath>
        <clipPath id="stripes"><path d="M19 10Q14.5 25 21.5 40H25Q20.33 25 23.33 10zM27.67 10Q26.17 25 28.5 40H35.5Q37.83 25 36.33 10zM40.67 10Q43.67 25 39 40H42.5Q49.5 25 45 10z" /></clipPath>
      </defs>
      <g clipPath="url(#sail)">
        <g clipPath="url(#stripes)">
          <path d="M12.5 14.60Q32 15.25 51.5 14.60M12.5 15.95Q32 16.71 51.5 15.95M12.5 17.30Q32 18.16 51.5 17.30M12.5 18.65Q32 19.62 51.5 18.65M12.5 20.00Q32 21.08 51.5 20.00M12.5 21.35Q32 22.54 51.5 21.35M12.5 22.70Q32 24.00 51.5 22.70M12.5 24.05Q32 25.45 51.5 24.05M12.5 25.40Q32 26.91 51.5 25.40M12.5 26.75Q32 28.37 51.5 26.75M12.5 28.10Q32 29.83 51.5 28.10M12.5 29.45Q32 31.29 51.5 29.45M12.5 30.80Q32 32.74 51.5 30.80M12.5 32.15Q32 34.20 51.5 32.15M12.5 33.50Q32 35.66 51.5 33.50M12.5 34.85Q32 37.12 51.5 34.85M12.5 36.20Q32 38.58 51.5 36.20M12.5 37.55Q32 40.03 51.5 37.55M12.5 38.90Q32 41.49 51.5 38.90" fill="none" stroke="#ededed" strokeWidth=".6" />
        </g>
      </g>
      <path d="M19 14H45Q49.5 25 42.5 37.5Q32 34.2 21.5 37.5Q14.5 25 19 14z" fill="none" stroke="#ededed" strokeWidth="1.3" strokeLinejoin="round" />
      <g fill="#ededed">
        <path d="M16.5 13.2q15.5-2.2 31 0v2.2q-15.5-2.2-31 0z" />
        <rect x="30.8" y="8" width="2.4" height="33" rx="1.2" />
        <path d="M6.5 27.5Q8.7 27.5 9.1 30.7Q10.5 39 17 39.5H47Q53.5 39 54.9 30.7Q55.3 27.5 57.5 27.5Q57.2 37.6 54.2 42.3Q50.5 47.5 44 47.5H20Q13.5 47.5 9.8 42.3Q6.8 37.6 6.5 27.5z" />
      </g>
      <path d="M22 46l-5 9M30 46l-5 9M38 46l-5 9M46 46l-5 9" stroke="#ededed" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

function Card({ eyebrow, title, subtitle, figures }: { eyebrow: string; title: string; subtitle: string; figures: [string, string][] }) {
  return (
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 72, background: "#0a0a0a", color: "#fafafa" }}>
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ fontSize: 30, color: "#34d399" }}>{eyebrow}</div>
          {figures.length > 0 && (
            <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 32, color: "#a1a1aa" }}>
              <Mark size={56} />
              {siteName}
            </div>
          )}
        </div>
        <div style={{ fontSize: 112, marginTop: 12, letterSpacing: -2 }}>{title}</div>
        <div style={{ fontSize: 40, color: "#d4d4d8", marginTop: 8 }}>{subtitle}</div>
      </div>
      <div style={{ display: "flex", gap: 72 }}>
        {figures.length === 0 && <Mark size={176} />}
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
