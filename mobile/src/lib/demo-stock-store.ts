import { createDemoData } from '@/data/demo';
import { createStore } from '@/lib/external-store';
import { addStock, replaceStock } from '@/lib/stocks';

const store = createStore({ trades: createDemoData().trades });
export const useStockTrades = () => store.useValue().trades;
export function saveDemoStock(ticker: string, quantity: number, price: number | undefined, editing: boolean) {
  store.set({ trades: (editing ? replaceStock : addStock)(store.get().trades, ticker, quantity, price) });
}
export function removeDemoStock(ticker: string) { store.set({ trades: store.get().trades.filter(trade => trade.ticker !== ticker) }); }
