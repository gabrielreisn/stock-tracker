import { isFGCCovered, today, valueBond, type BondRates, type BondValuation } from '@/lib/bonds';
import type { Bond, Conglomerate, Conglomerates } from '@/types';

export const FGC_INSTITUTION_LIMIT = 250_000;
export const FGC_OVERALL_LIMIT = 1_000_000;
export interface Exposure {
  key: string;
  names: string[];
  cnpjs: string[];
  conglomerate?: Conglomerate;
  bonds: { bond: Bond; value: BondValuation | null }[];
  // Never silently sum partial valuations: missing interest could hide a breached limit.
  gross: number | null;
  atMaturity: number | null;
}
export const cnpjDigits = (value = '') => value.replace(/\D/g, '');
export const foldIssuer = (value: string) => value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}]/gu, '');
export function formatCNPJ(value: string) {
  return value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
}
export function fgcStatus(gross: number | null) {
  return gross === null ? 'unknown' : gross > FGC_INSTITUTION_LIMIT ? 'above' : gross > FGC_INSTITUTION_LIMIT * .8 ? 'near' : 'within';
}
export function buildFGC(bonds: Bond[], rates: BondRates | null, conglomerates: Conglomerates, day = today()) {
  const groups = new Map<string, Exposure>();
  for (const bond of bonds) {
    if (!isFGCCovered(bond.kind) || bond.maturityDay < day || bond.issueDay > day) continue;
    const digits = cnpjDigits(bond.issuerCNPJ);
    const root = digits.length === 14 ? digits.slice(0, 8) : null;
    const conglomerate = root ? conglomerates[root] : undefined;
    const key = conglomerate?.code ?? root ?? `name:${foldIssuer(bond.issuer)}`;
    const group = groups.get(key) ?? { key, names: [], cnpjs: [], bonds: [], conglomerate, gross: null, atMaturity: null };
    if (!group.names.includes(bond.issuer)) group.names.push(bond.issuer);
    if (root && !group.cnpjs.includes(digits)) group.cnpjs.push(digits);
    group.bonds.push({ bond, value: valueBond(bond, rates, day) });
    groups.set(key, group);
  }
  const exposures = [...groups.values()];
  for (const group of exposures) {
    if (group.bonds.every(row => row.value !== null)) {
      group.gross = group.bonds.reduce((sum, row) => sum + row.value!.gross, 0);
      group.atMaturity = group.bonds.reduce((sum, row) => sum + (row.value!.atMaturity ?? row.value!.gross), 0);
    }
  }
  exposures.sort((a, b) => (b.gross ?? -1) - (a.gross ?? -1) || a.key.localeCompare(b.key));
  const complete = exposures.every(group => group.gross !== null);
  const guaranteed = complete ? exposures.reduce((sum, group) => sum + Math.min(group.gross!, FGC_INSTITUTION_LIMIT), 0) : null;
  const above = complete ? exposures.reduce((sum, group) => sum + Math.max(0, group.gross! - FGC_INSTITUTION_LIMIT), 0) : null;
  const uncovered = bonds.filter(bond => !isFGCCovered(bond.kind)).map(bond => ({ bond, value: valueBond(bond, rates, day) }));
  return { exposures, guaranteed, above, uncovered };
}

interface InstitutionRow { CodInst: string; NomeInstituicao?: string; CodConglomeradoPrudencial?: string | null }
export function parseConglomerates(rows: InstitutionRow[]): Conglomerates {
  const names = new Map(rows.map(row => [row.CodInst, row.NomeInstituicao ?? row.CodInst]));
  const institutions = rows.filter(row => /^\d{8}$/.test(row.CodInst));
  const result: Conglomerates = {};
  for (const row of institutions) {
    const code = row.CodConglomeradoPrudencial;
    if (!code) continue;
    result[row.CodInst] = {
      code, name: (names.get(code) ?? code).replace(' - PRUDENCIAL', ''),
      members: institutions.filter(member => member.CodConglomeradoPrudencial === code)
        .flatMap(member => member.NomeInstituicao ? [member.NomeInstituicao] : []).sort(),
    };
  }
  return result;
}
/** Try the last three completed quarters concurrently; prefer the newest published one. */
export async function fetchConglomerates(signal: AbortSignal, day = today()): Promise<Conglomerates> {
  const quarters: number[] = [];
  const date = new Date(Date.UTC(Math.floor(day / 10000), Math.floor(day / 100) % 100 - 1, 1));
  while (quarters.length < 3) {
    date.setUTCMonth(date.getUTCMonth() - 1);
    if ((date.getUTCMonth() + 1) % 3 === 0) quarters.push(date.getUTCFullYear() * 100 + date.getUTCMonth() + 1);
  }
  const responses = await Promise.all(quarters.map(async quarter => {
    try {
      const url = `https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/odata/IfDataCadastro(AnoMes=@AnoMes)?@AnoMes=${quarter}&$select=CodInst,NomeInstituicao,CodConglomeradoPrudencial&$format=json`;
      const response = await fetch(url, { signal });
      if (!response.ok) return null;
      const data = await response.json();
      if (!Array.isArray(data.value)) return null;
      const rows = data.value.filter((row: InstitutionRow) => row && typeof row.CodInst === 'string' && (row.NomeInstituicao == null || typeof row.NomeInstituicao === 'string') && (row.CodConglomeradoPrudencial == null || typeof row.CodConglomeradoPrudencial === 'string'));
      const groups = parseConglomerates(rows);
      return Object.keys(groups).length ? groups : null;
    } catch { return null; }
  }));
  const newest = responses.find(result => result !== null);
  if (!newest) throw new Error('Conglomerates unavailable');
  return newest;
}
