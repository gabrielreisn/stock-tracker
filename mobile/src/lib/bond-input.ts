import { dateFromDay, dayFromDate, today } from '@/lib/bonds';
import { t } from '@/lib/i18n';
import type { Bond, BondIndexer } from '@/types';

export const indexerLabel = (value: BondIndexer) => t(({ fixed: 'Fixed rate', cdi: '% of CDI', cdiPlus: 'CDI + spread', ipca: 'IPCA + spread' } as const)[value]);
export const inputDate = (day: number) => dateFromDay(day).toISOString().slice(0, 10);
export function parseDate(text: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null;
  const date = new Date(`${text}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== text) return null;
  const day = dayFromDate(date);
  return day >= 20000101 && day <= 20701231 ? day : null;
}
export function parseBondNumber(text: string) {
  const normalized = text.trim().includes(',') ? text.trim().replace(/\./g, '').replace(',', '.') : text.trim();
  return /^\d+(\.\d+)?$/.test(normalized) ? Number(normalized) : NaN;
}

function defaultMaturity() {
  const date = dateFromDay(today());
  const year = date.getUTCFullYear() + 2;
  const day = Math.min(date.getUTCDate(), new Date(Date.UTC(year, date.getUTCMonth() + 1, 0)).getUTCDate());
  return dayFromDate(new Date(Date.UTC(year, date.getUTCMonth(), day)));
}
export function initialBondDraft(bond: Bond | null) {
  return {
    kind: bond?.kind ?? 'CDB', issuer: bond?.issuer ?? '', cnpj: bond?.issuerCNPJ ?? '', code: bond?.code ?? '',
    issued: inputDate(bond?.issueDay ?? today()), matures: inputDate(bond?.maturityDay ?? defaultMaturity()),
    indexer: bond?.indexer ?? 'fixed', rate: bond ? String(bond.rate).replace('.', ',') : '', quantity: bond ? String(bond.quantity).replace('.', ',') : '', price: String(bond?.unitPrice ?? 1000).replace('.', ','),
  };
}

export function validateBondDraft(draft: ReturnType<typeof initialBondDraft>) {
  const rate = parseBondNumber(draft.rate), quantity = parseBondNumber(draft.quantity), price = parseBondNumber(draft.price);
  const issueDay = parseDate(draft.issued), maturityDay = parseDate(draft.matures), digits = draft.cnpj.replace(/\D/g, '');
  const valid = !!draft.issuer.trim() && [rate, quantity, price, quantity * price].every(v => Number.isFinite(v) && v > 0) && issueDay !== null && maturityDay !== null && maturityDay > issueDay && (!draft.cnpj.trim() || digits.length === 14);
  return { rate, quantity, price, issueDay, maturityDay, digits, valid };
}
