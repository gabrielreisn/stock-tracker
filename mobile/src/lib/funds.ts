import { fundStore } from '@/lib/account-store';
import type { FundHolding, FundPurpose } from '@/types';
export { fundStore } from '@/lib/account-store';

export function saveFund(holding: FundHolding) {
  const holdings = fundStore.get().holdings;
  const exists = holdings.some((fund) => fund.id === holding.id);
  fundStore.set({
    holdings: exists
      ? holdings.map((fund) => (fund.id === holding.id ? holding : fund))
      : [...holdings, holding],
  });
}
export function deleteFund(id: string) {
  fundStore.set({
    holdings: fundStore.get().holdings.filter((fund) => fund.id !== id),
  });
}
export function fundPurpose(fund: FundHolding): FundPurpose {
  if (fund.purpose) return fund.purpose;
  const name = fund.name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase();
  if (name.includes('SELIC')) return 'selic';
  if (/IPCA|INFLA/.test(name)) return 'inflation';
  if (fund.kind === 'fip') return 'infrastructure';
  if (name.includes(' ACOES')) return 'equities';
  if (fund.kind === 'fidc' || /CRED| CP |CRPR/.test(name)) return 'credit';
  return 'other';
}
export const purposes = [
  'selic',
  'credit',
  'inflation',
  'infrastructure',
  'equities',
  'other',
] as const;
export const purposeLabels = {
  selic: 'Selic / DI',
  credit: 'Private credit (CDI)',
  inflation: 'Inflation (IPCA)',
  infrastructure: 'Infrastructure (FIP)',
  equities: 'Equities',
  other: 'Other',
} as const;
export function grossValue(fund: FundHolding): number | undefined {
  if (!fund.statementPrice || !fund.statementDay) return undefined;
  const value = fund.quantity * fund.statementPrice;
  return Number.isFinite(value) ? value : undefined;
}
export function formatCNPJ(value: string) {
  return value.replace(
    /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
    '$1.$2.$3/$4-$5',
  );
}
export function parseDecimal(value: string): number | undefined {
  const normalized = value.trim().replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(normalized)) return undefined;
  const result = Number(normalized);
  return Number.isFinite(result) && result > 0 ? result : undefined;
}
export function parseDay(value: string): number | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  const date = new Date(`${value}T12:00:00Z`);
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== value
  )
    return undefined;
  const today = new Date();
  const todayKey =
    today.getFullYear() * 10000 +
    (today.getMonth() + 1) * 100 +
    today.getDate();
  const key = Number(value.replaceAll('-', ''));
  return key <= todayKey ? key : undefined;
}
export function dayInput(day?: number) {
  const date = new Date();
  const key = String(
    day ??
      date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate(),
  );
  return `${key.slice(0, 4)}-${key.slice(4, 6)}-${key.slice(6, 8)}`;
}
export const money = (value: number | undefined) =>
  value === undefined
    ? '—'
    : value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const shares = (value: number) =>
  value.toLocaleString('pt-BR', { maximumFractionDigits: 8 });
