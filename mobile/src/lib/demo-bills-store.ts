import { createDemoData } from '@/data/demo';
import { createStore } from '@/lib/external-store';
import { todayKey, withBillChoice } from '@/lib/bills';
import type { BillChoice } from '@/types';

// Kept separate from the personal Pluggy store. Edits last for this app session only.
const account = createDemoData();
export const demoBillsStore = createStore({ data: account, day: todayKey() });

export function updateDemoBill(key: string, change: Partial<BillChoice>) {
  const { data } = demoBillsStore.get();
  demoBillsStore.set({ data: { ...data, expenses: withBillChoice(data.expenses, key, change) } });
}

export function refreshDemoBills() {
  const { data, day } = demoBillsStore.get();
  const today = todayKey();
  if (day === today) return;
  demoBillsStore.set({ data: { ...createDemoData(today), expenses: data.expenses }, day: today });
}
