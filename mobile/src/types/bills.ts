import type { Expense, ExpenseSource } from './expenses';

export type BillStatus = 'paid' | 'upcoming' | 'late';
export interface RecurringBill {
  key: string;
  name: string;
  source: ExpenseSource;
  dueDay: number;
  dueDaySet: boolean;
  usual: number;
  lastPayment: Expense;
  paidThisMonth: Expense[];
  paidByHand: boolean;
  installment?: { number: number; total: number };
  trackedByHand: boolean;
  nextDue: number;
  status: BillStatus;
}

export interface CardBillGroup {
  key: string;
  account?: import('./pluggy').PluggyAccount;
  bills: import('./pluggy').PluggyBill[];
}
