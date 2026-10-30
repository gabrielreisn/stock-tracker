// Brazilian formatting for the figures on asset pages.

const symbols: Record<string, string> = { BRL: "R$", USD: "US$" };

const fixed = (x: number, digits: number) =>
  x.toLocaleString("pt-BR", { minimumFractionDigits: digits, maximumFractionDigits: digits });

export const percent = (x: number | null | undefined, digits = 2) => (x == null ? "—" : `${fixed(x * 100, digits)}%`);
export const money = (x: number, currency: string, digits = 2) => `${symbols[currency] ?? currency} ${fixed(x, digits)}`;
export const decimal = (x: number | null | undefined, digits = 2) => (x == null ? "—" : fixed(x, digits));

/** "2026-10-29" → "29/10/2026", "2026-10" → "10/2026", "1953" → "1953". */
export function date(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return d ? `${d}/${m}/${y}` : m ? `${m}/${y}` : y;
}
