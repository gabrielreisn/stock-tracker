import { createDemoData } from '../data/demo';
import type { ExpenseSettings } from '../types';
import { createStore } from './external-store';

// This account is intentionally in memory and never shares the personal Pluggy store.
export const demoExpenseAccount = createDemoData();
export const demoExpenseStore = createStore<{ settings: ExpenseSettings }>({ settings: demoExpenseAccount.expenses });
