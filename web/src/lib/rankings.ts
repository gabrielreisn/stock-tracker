import bdrs from "@/data/assets/bdrs.json";
import brStocks from "@/data/assets/br-stocks.json";
import fiis from "@/data/assets/fiis.json";
import usETFs from "@/data/assets/us-etfs.json";
import type { AssetList } from "@/lib/assets";

// The rankings behind each list (src/data/assets/<list>.json, written by scripts/most-traded.mjs).

export type Ranking = typeof brStocks;

export const rankings: Record<AssetList, Ranking> = { "br-stocks": brStocks, fiis, "us-etfs": usETFs, bdrs };

/** Yahoo Finance's symbol for a listed ticker: B3 tickers carry ".SA". */
export const yahooSymbol = (list: AssetList, ticker: string) => (list === "us-etfs" ? ticker : `${ticker}.SA`);
