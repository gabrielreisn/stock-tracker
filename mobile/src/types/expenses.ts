import type { DayKey, MonthKey, UUID } from './portfolio';

export interface ExpenseCategory {
  id: UUID;
  name: string;
  /** SF Symbol name from macOS; mobile consumers must map it for their platform. */
  symbol: string;
  limit?: number;
  pluggyKeywords: string[];
}

export interface ManualExpense {
  id: UUID;
  day: DayKey;
  store: string;
  amount: number;
  categoryID?: UUID;
}

/** Swift Codable associated-value enum, preserving the macOS JSON wire format. */
export type ExpenseOverride =
  | { category: { _0: UUID }; outside?: never; deleted?: never }
  | { outside: Record<string, never>; category?: never; deleted?: never }
  | { deleted: Record<string, never>; category?: never; outside?: never };

export interface BillChoice {
  tracked?: boolean;
  dueDay?: number;
  paidByHand?: MonthKey[];
}

export interface ExpenseSettings {
  categories: ExpenseCategory[];
  rules: Record<string, UUID>;
  overrides: Record<string, ExpenseOverride>;
  manual: ManualExpense[];
  totalLimit?: number;
  /** Fraction of the limit, e.g. 0.8, not 80. */
  alertAt: number;
  largePurchase?: number;
  notified: string[];
  bills?: Record<string, BillChoice>;
}

export type ExpenseSource = 'pix' | 'creditCard' | 'debitCard' | 'autoDebit'
  | 'transfer' | 'boleto' | 'account' | 'manual';

/** Classified UI row, derived from a transaction or a manual expense. */
export interface Expense {
  id: string;
  day: DayKey;
  store: string;
  detail: string;
  amount: number;
  kind: 'spending' | 'income' | 'outside';
  categoryID?: UUID;
  accountName?: string;
  isCard: boolean;
  isManual: boolean;
  installment?: string;
  merchantKey: string;
  source: ExpenseSource;
  billedLater: boolean;
  foreign?: {
    amount: number;
    currency: string;
    conversion: { kind: 'bank' } | { kind: 'rate'; rate: number } | { kind: 'missing' };
  };
}
