import Storage from 'expo-sqlite/kv-store';
import categories from '@/data/default-categories.json';
import { createStore } from '@/lib/external-store';
import type { DemoData, ExpenseSettings, PluggyBill, PluggyLoan } from '@/types';

export interface AccountData extends DemoData {
  cardBills: PluggyBill[];
  loans: PluggyLoan[];
}
const KEY = 'personal-account-v1';

export function emptyAccount(): AccountData {
  return {
    trades: [], bonds: [], fundHoldings: [], alerts: [], cardBills: [], loans: [],
    expenses: { categories: categories.map(row => ({ ...row, pluggyKeywords: [...row.pluggyKeywords] })),
      rules: {}, overrides: {}, manual: [], alertAt: 0.8, notified: [] },
    transactions: { months: {}, fetchedAt: {}, accounts: [], currencyRead: [] },
  };
}

function load(): AccountData {
  try {
    const saved = Storage.getItemSync(KEY);
    if (saved) return { ...emptyAccount(), ...JSON.parse(saved) };
  } catch { /* An unreadable personal cache starts empty, never with demo positions. */ }
  return emptyAccount();
}

const store = createStore({ data: load() });
export const accountStore = {
  get: store.get,
  useValue: store.useValue,
  set({ data }: { data: AccountData }) {
    Storage.setItemSync(KEY, JSON.stringify(data));
    store.set({ data });
  },
};
export const expenseStore = {
  get: () => ({ settings: accountStore.get().data.expenses }),
  useValue: () => ({ settings: accountStore.useValue().data.expenses }),
  set({ settings }: { settings: ExpenseSettings }) {
    accountStore.set({ data: { ...accountStore.get().data, expenses: settings } });
  },
};

export const fundStore = {
  get: () => ({ holdings: accountStore.get().data.fundHoldings }),
  useValue: () => ({ holdings: accountStore.useValue().data.fundHoldings }),
  set({ holdings }: { holdings: AccountData['fundHoldings'] }) {
    accountStore.set({ data: { ...accountStore.get().data, fundHoldings: holdings } });
  },
};
