import { accountStore } from '@/lib/account-store';
import { addStock, replaceStock } from '@/lib/stocks';

const store = {
  get: () => ({ trades: accountStore.get().data.trades }),
  useValue: () => ({ trades: accountStore.useValue().data.trades }),
  set({ trades }: { trades: import('@/types').Trade[] }) {
    accountStore.set({ data: { ...accountStore.get().data, trades } });
  },
};
export const useStockTrades = () => store.useValue().trades;
export function saveStock(ticker: string, quantity: number, price: number | undefined, editing: boolean) {
  store.set({ trades: (editing ? replaceStock : addStock)(store.get().trades, ticker, quantity, price) });
}
export function removeStock(ticker: string) { store.set({ trades: store.get().trades.filter(trade => trade.ticker !== ticker) }); }
