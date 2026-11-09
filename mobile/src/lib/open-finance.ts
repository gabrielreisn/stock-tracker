import type { Bond, BondIndexer, BondKind, FundHolding, PluggyInvestment, Trade } from '@/types';
import type { AccountData } from '@/lib/account-store';

export const SYNC_INTERVAL_MS = 6 * 60 * 60 * 1000;
export function syncIsDue(lastSync: Date | null, now = Date.now()) {
  return lastSync === null || now - lastSync.getTime() >= SYNC_INTERVAL_MS;
}
const PREFIX = 'pluggy-';
export function investmentCode(inv: PluggyInvestment) {
  return (inv.code ?? '').trim().toUpperCase().replace(/^CDB-/, '');
}
function day(iso?: string | null) {
  const value = Number(iso?.slice(0, 10).replaceAll('-', ''));
  return value >= 19000101 && value <= 99991231 ? value : undefined;
}
export function isClosedInvestment(inv: PluggyInvestment) {
  return inv.status === 'TOTAL_WITHDRAWAL' || ((inv.quantity ?? 0) === 0 && (inv.balance ?? inv.amount ?? 0) === 0);
}
function cost(inv: PluggyInvestment): number | undefined {
  if (!inv.quantity || inv.quantity <= 0) return undefined;
  const original = inv.amountOriginal ?? ((inv.amount ?? inv.balance ?? 0) - (inv.amountProfit ?? 0));
  // A gross balance alone is not an acquisition cost.
  if (inv.amountOriginal == null && inv.amountProfit == null) return undefined;
  return original > 0 ? original / inv.quantity : undefined;
}
function fundCNPJ(inv: PluggyInvestment) {
  return [inv.code, inv.number].map(value => (value ?? '').replace(/\D/g, '')).find(value => value.length === 14);
}
function groupKey(inv: PluggyInvestment) {
  const code = inv.type === 'MUTUAL_FUND' ? fundCNPJ(inv) : investmentCode(inv);
  return `${inv.type}:${code || inv.id}`;
}
export function investmentKey(inv: PluggyInvestment) { return PREFIX + groupKey(inv); }

/** Import reported positions, never invent bond terms or a fund's identity. */
export function reconcilePortfolio(previous: AccountData, investments: PluggyInvestment[], today: number): AccountData {
  const trades: Trade[] = [];
  const bonds: Bond[] = [];
  const funds: FundHolding[] = [];
  const groups = new Map<string, PluggyInvestment[]>();
  for (const inv of investments) {
    if (isClosedInvestment(inv) || !(inv.quantity && inv.quantity > 0)) continue;
    const key = groupKey(inv);
    groups.set(key, [...(groups.get(key) ?? []), inv]);
  }
  for (const [key, entries] of groups) {
    const inv = entries[0];
    const id = PREFIX + key;
    const quantity = entries.reduce((sum, row) => sum + (row.quantity ?? 0), 0);
    const priced = entries.filter(row => cost(row) !== undefined);
    const shares = priced.reduce((sum, row) => sum + row.quantity!, 0);
    const average = shares > 0 ? priced.reduce((sum, row) => sum + cost(row)! * row.quantity!, 0) / shares : undefined;
    const code = investmentCode(inv);
    if ((inv.type === 'EQUITY' || inv.type === 'ETF') && /^[A-Z][A-Z0-9.\-]{0,19}$/.test(code)) {
      const ticker = /^\w{4}\d{1,2}F$/.test(code) ? code.slice(0, -1) : code;
      const old = previous.trades.find(trade => trade.id === id);
      // Holdings snapshots aren't a full trade history. Start on import day unless we already track this position.
      trades.push({ id, ticker, kind: 'buy', quantity, price: average ?? old?.price,
        date: old?.date ?? `${String(today).slice(0, 4)}-${String(today).slice(4, 6)}-${String(today).slice(6, 8)}T12:00:00Z` });
    } else if (inv.type === 'FIXED_INCOME') {
      const subtype = (inv.subtype ?? '').toUpperCase();
      const kinds: Record<string, BondKind> = { CDB: 'CDB', LCA: 'LCA', LCI: 'LCI', LC: 'LC', CRI: 'CRI', CRA: 'CRA',
        DEBENTURE: 'Debênture', INCENTIVIZED_DEBENTURE: 'Debênture incentivada' };
      const kind = kinds[subtype];
      const issueDay = day(inv.issueDate ?? inv.purchaseDate);
      const maturityDay = day(inv.dueDate);
      if (!kind || !issueDay || !maturityDay || maturityDay < issueDay || average === undefined) continue;
      const index = (inv.rateType ?? '').toUpperCase();
      const share = inv.rate ?? 0;
      const fixed = inv.fixedAnnualRate ?? 0;
      let indexer: BondIndexer;
      let rate: number;
      if (index.includes('IPCA')) { indexer = 'ipca'; rate = fixed > 0 ? fixed : share; }
      else if (share === 0) { indexer = 'fixed'; rate = fixed; }
      else if (/CDI|SELIC|^DI$/.test(index)) { indexer = fixed > 0 ? 'cdiPlus' : 'cdi'; rate = fixed > 0 ? fixed : share; }
      else { indexer = 'fixed'; rate = fixed > 0 ? fixed : share; }
      if (inv.rate == null && inv.fixedAnnualRate == null) continue;
      bonds.push({ id, kind, code, issuer: inv.issuer ?? inv.name ?? code, issuerCNPJ: inv.issuerCNPJ ?? undefined,
        issueDay, maturityDay, indexer, rate, quantity, unitPrice: average });
    } else if (inv.type === 'MUTUAL_FUND') {
      const cnpj = fundCNPJ(inv);
      if (!cnpj) continue;
      const name = inv.name ?? cnpj;
      const kind = /FIDC/i.test(`${inv.subtype} ${name}`) ? 'fidc' : /FIP/i.test(`${inv.subtype} ${name}`) ? 'fip' : 'fif';
      const latest = [...entries].sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''))[0];
      const price = latest.value ?? (latest.amount && latest.quantity ? latest.amount / latest.quantity : undefined);
      const old = previous.fundHoldings.find(fund => fund.cnpj === cnpj);
      funds.push({ ...old, id, cnpj, name, kind, quantity, taxExempt: old?.taxExempt ?? /INCENT|INFRA/i.test(name),
        statementPrice: price ?? old?.statementPrice, statementDay: day(latest.date) ?? old?.statementDay,
        statementFromOpenFinance: true });
    }
  }
  return { ...previous,
    trades: [...previous.trades.filter(row => row.id.startsWith(PREFIX)
      ? groups.has(row.id.slice(PREFIX.length)) && !trades.some(trade => trade.id === row.id)
      : !trades.some(trade => trade.ticker === row.ticker)), ...trades],
    bonds: [...previous.bonds.filter(row => row.id.startsWith(PREFIX)
      ? groups.has(row.id.slice(PREFIX.length)) && !bonds.some(bond => bond.id === row.id)
      : !bonds.some(bond => bond.code === row.code)), ...bonds],
    fundHoldings: [...previous.fundHoldings.filter(row => row.id.startsWith(PREFIX)
      ? groups.has(row.id.slice(PREFIX.length)) && !funds.some(fund => fund.id === row.id)
      : !funds.some(fund => fund.cnpj === row.cnpj)), ...funds],
  };
}
