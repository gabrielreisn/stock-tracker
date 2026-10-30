// Brazilian formatting for figures that go into generated pages: the model copies these strings, it never formats.
const fixed = (x, digits) => x.toLocaleString("pt-BR", { minimumFractionDigits: digits, maximumFractionDigits: digits });
const symbols = { BRL: "R$", USD: "US$" };

export const percent = (x, digits = 2) => (x == null ? null : `${fixed(x * 100, digits)}%`);
export const money = (x, currency = "BRL", digits = 2) => (x == null ? null : `${symbols[currency] ?? currency} ${fixed(x, digits)}`);
export const integer = (x) => Math.round(x).toLocaleString("pt-BR");

export function bigMoney(x, currency = "BRL") {
  if (x == null) return null;
  const symbol = symbols[currency] ?? currency;
  if (x >= 1e9) return `${symbol} ${fixed(x / 1e9, 2)} ${x >= 2e9 ? "bilhões" : "bilhão"}`;
  if (x >= 1e6) return `${symbol} ${fixed(x / 1e6, 1)} ${x >= 2e6 ? "milhões" : "milhão"}`;
  return money(x, currency);
}

/** "2026-10-29" → "29/10/2026", "2026-10" → "10/2026". */
export function date(iso) {
  if (!iso) return null;
  const [y, m, d] = iso.slice(0, 10).split("-");
  return d ? `${d}/${m}/${y}` : m ? `${m}/${y}` : y;
}

/** "29/10/2026" or "10/2026" → ISO; null for B3's 31/12/9999 placeholder. */
export function isoDate(br) {
  const m = br?.match(/^(?:(\d{2})\/)?(\d{2})\/(\d{4})/);
  if (!m || +m[3] > 2100) return null;
  return m[1] ? `${m[3]}-${m[2]}-${m[1]}` : `${m[3]}-${m[2]}`;
}

const lowercaseWords = new Set(["de", "da", "do", "das", "dos", "e", "em"]);
/** "RIO DE JANEIRO" → "Rio de Janeiro". For place names; legal names stay as registered. */
export const titleCase = (s) =>
  s.toLowerCase().replace(/\S+/g, (w, at) => (at && lowercaseWords.has(w) ? w : w[0].toUpperCase() + w.slice(1)));

/** First letter up, the rest as is: "ESTATAL HOLDING" → "Estatal holding". */
export const sentenceCase = (s) => (s ? s[0].toUpperCase() + s.slice(1).toLowerCase() : s);
