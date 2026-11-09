/** JSON contracts ported from macOS Models.swift, Bonds.swift and FundHoldings.swift. */
export type UUID = string;
/** Calendar date as YYYYMMDD, independent of timezone. */
export type DayKey = number;
/** Calendar month as YYYYMM (object keys are its string representation). */
export type MonthKey = number;
export type ISODateString = string;
/** Swift JSONEncoder's default Date representation: seconds since 2001-01-01 UTC. */
export type AppleTimestamp = number;
export type BenchmarkId = 'cdi' | 'ipca' | 'sp500' | 'ipcaPlus6' | 'ifix' | 'ibov';
export type TradeKind = 'buy' | 'sell';

export interface Trade {
  id: UUID;
  ticker: string;
  kind: TradeKind;
  date: ISODateString;
  quantity: number;
  /** Per share in the ticker's currency; absent means use its historical close. */
  price?: number;
}

export interface PriceAlert {
  id: UUID;
  ticker: string;
  target: number;
  kind: TradeKind;
  isEnabled: boolean;
  triggeredAt?: ISODateString;
}

export type BondKind = 'CDB' | 'LCA' | 'LCI' | 'LC' | 'CRI' | 'CRA'
  | 'Debênture' | 'Debênture incentivada';
export type BondIndexer = 'fixed' | 'cdi' | 'cdiPlus' | 'ipca';

export interface Bond {
  id: UUID;
  kind: BondKind;
  issuer: string;
  issuerCNPJ?: string;
  code: string;
  issueDay: DayKey;
  maturityDay: DayKey;
  indexer: BondIndexer;
  /** Percent: annual for fixed, share of CDI for cdi, annual spread for cdiPlus/ipca. */
  rate: number;
  quantity: number;
  unitPrice: number;
}

export type FundHoldingKind = 'fif' | 'fidc' | 'fip';
export type FundPurpose = 'selic' | 'credit' | 'inflation' | 'infrastructure' | 'equities' | 'other';
export interface FundHolding {
  id: UUID;
  cnpj: string;
  name: string;
  kind: FundHoldingKind;
  quantity: number;
  taxExempt: boolean;
  statementPrice?: number;
  statementDay?: DayKey;
  statementFromOpenFinance?: boolean;
  purpose?: FundPurpose;
}

export interface PriceHistory {
  /** Ascending days; prices has the same length. Adjusted closes in ticker currency. */
  days: DayKey[];
  prices: number[];
  name?: string;
  dividends?: { day: DayKey; amount: number }[];
}

export interface RatePoint {
  day: DayKey;
  /** Percent per business day for CDI; percent per month for IPCA. */
  rate: number;
}
