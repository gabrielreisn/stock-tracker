/** Fields consumed by macOS Pluggy.swift; API fields may be omitted or null. */
import type { ISODateString } from './portfolio';

export interface PluggyItem {
  id: string;
  status?: string | null;
  executionStatus?: string | null;
  updatedAt?: ISODateString | null;
  lastUpdatedAt?: ISODateString | null;
  connector?: { id?: number | null; name?: string | null; imageUrl?: string | null } | null;
  error?: { code?: string | null; message?: string | null } | null;
}

export interface PluggyAccount {
  id: string;
  itemId?: string | null;
  type?: string | null;
  subtype?: string | null;
  name?: string | null;
  marketingName?: string | null;
  number?: string | null;
  balance?: number | null;
  currencyCode?: string | null;
}

export interface PluggyTransaction {
  id: string;
  accountId?: string | null;
  description?: string | null;
  descriptionRaw?: string | null;
  amount?: number | null;
  currencyCode?: string | null;
  amountInAccountCurrency?: number | null;
  date?: ISODateString | null;
  type?: string | null;
  category?: string | null;
  status?: string | null;
  merchant?: PluggyMerchant | null;
  creditCardMetadata?: PluggyCardMetadata | null;
  paymentData?: PluggyPaymentData | null;
}

export interface PluggyInvestment {
  id: string;
  itemId?: string | null;
  name?: string | null;
  code?: string | null;
  isin?: string | null;
  number?: string | null;
  type?: string | null;
  subtype?: string | null;
  status?: string | null;
  balance?: number | null;
  amount?: number | null;
  amountOriginal?: number | null;
  amountProfit?: number | null;
  quantity?: number | null;
  value?: number | null;
  taxes?: number | null;
  taxes2?: number | null;
  issuer?: string | null;
  issuerCNPJ?: string | null;
  issueDate?: ISODateString | null;
  purchaseDate?: ISODateString | null;
  dueDate?: ISODateString | null;
  date?: ISODateString | null;
  rate?: number | null;
  rateType?: string | null;
  fixedAnnualRate?: number | null;
  lastMonthRate?: number | null;
  lastTwelveMonthsRate?: number | null;
  currencyCode?: string | null;
}

export interface PluggyBill {
  id: string;
  accountId?: string | null;
  dueDate?: ISODateString | null;
  billClosingDate?: ISODateString | null;
  totalAmount?: number | null;
  totalAmountCurrencyCode?: string | null;
  minimumPaymentAmount?: number | null;
  payments?: { paymentDate?: string | null; amount?: number | null }[] | null;
}

export interface PluggyLoan {
  id: string;
  itemId?: string | null;
  productName?: string | null;
  type?: string | null;
  contractAmount?: number | null;
  currencyCode?: string | null;
  contractDate?: ISODateString | null;
  dueDate?: ISODateString | null;
  firstInstallmentDueDate?: ISODateString | null;
  installmentPeriodicity?: string | null;
  installments?: PluggyLoanInstallments | null;
  payments?: PluggyLoanPayments | null;
}

export interface PluggyMerchant {
  name?: string | null;
  businessName?: string | null;
  cnpj?: string | null;
  category?: string | null;
}

export interface PluggyCardMetadata {
  installmentNumber?: number | null;
  totalInstallments?: number | null;
  totalAmount?: number | null;
  purchaseDate?: ISODateString | null;
  billId?: string | null;
}

export interface PluggyPaymentData {
  payer?: { name?: string | null } | null;
  receiver?: { name?: string | null } | null;
  paymentMethod?: string | null;
}

export interface PluggyLoanInstallments {
  totalNumberOfInstallments?: number | null;
  contractRemainingNumber?: number | null;
  paidInstallments?: number | null;
  dueInstallments?: number | null;
  pastDueInstallments?: number | null;
}

export interface PluggyLoanPayments {
  contractOutstandingBalance?: number | null;
  releases?: { paidDate?: ISODateString | null; paidAmount?: number | null }[] | null;
}
