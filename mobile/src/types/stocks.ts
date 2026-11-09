import type { PriceHistory } from './portfolio';

export interface StockQuote {
  history: PriceHistory;
  price?: number;
  previousClose?: number;
  asOf?: string;
}
export interface StockHolding {
  ticker: string;
  quantity: number;
  averagePrice?: number;
}
export interface StockPoint { day: number; value: number }
export type StockRange = '1M' | '3M' | '6M' | 'YTD' | '1Y' | '5Y';
export type StockSort = 'ticker' | 'shares' | 'average' | 'price' | 'value' | 'gain' | 'today' | 'ytd';
