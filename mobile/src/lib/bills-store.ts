import { accountStore, expenseStore } from '@/lib/account-store';
import { todayKey, withBillChoice } from '@/lib/bills';
import { sync } from '@/lib/pluggy-store';
import type { BillChoice } from '@/types';
export const billsStore = {
  get: () => ({ ...accountStore.get(), day: todayKey() }),
  useValue: () => ({ ...accountStore.useValue(), day: todayKey() }),
};
export function updateBill(key: string, change: Partial<BillChoice>) {
  expenseStore.set({ settings: withBillChoice(accountStore.get().data.expenses, key, change) });
}
export function refreshBills() { void sync(); }
