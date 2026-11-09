import { Unzip, UnzipInflate } from 'fflate';
import type { PriceHistory } from '@/types';

export type FundReportKind = 'fif' | 'fidc';
export type FundHistories = Record<string, PriceHistory>;

// Parse only needed columns and holdings. Numeric fields and CNPJs are ASCII in CVM's Windows-1252 CSVs.
export function createQuotaParser(kind: FundReportKind, ids: Set<string>) {
  const points = new Map<
    string,
    Map<number, { price: number; shares: number }>
  >();
  let columns: string[] | undefined;
  let tail = '';
  function line(text: string) {
    const fields = text.replace(/\r$/, '').split(';');
    if (!columns) {
      columns = fields;
      const required = [
        'DT_COMPTC',
        kind === 'fif' ? 'VL_QUOTA' : 'TAB_X_VL_COTA',
      ];
      if (
        !fields.some(
          (field) => field === 'CNPJ_FUNDO_CLASSE' || field === 'CNPJ_FUNDO',
        ) ||
        required.some((field) => !fields.includes(field))
      )
        throw new Error('Invalid CVM report columns');
      return;
    }
    const get = (...names: string[]) => {
      for (const name of names) {
        const index = columns!.indexOf(name);
        if (index >= 0) return fields[index] ?? '';
      }
      return '';
    };
    const id = get('CNPJ_FUNDO_CLASSE', 'CNPJ_FUNDO').replace(/\D/g, '');
    if (!ids.has(id)) return;
    // Match desktop's unsuffixed class series; never mix subclasses into a FIF history.
    if (kind === 'fif' && get('ID_SUBCLASSE').trim()) return;
    const date = get('DT_COMPTC');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
    const day = Number(date.replaceAll('-', ''));
    const price = Number(get(kind === 'fif' ? 'VL_QUOTA' : 'TAB_X_VL_COTA'));
    const shares = Number(get('TAB_X_QT_COTA')) || 0;
    if (!Number.isFinite(price) || price <= 0) return;
    let rows = points.get(id);
    if (!rows) {
      rows = new Map();
      points.set(id, rows);
    }
    const previous = rows.get(day);
    // Desktop uses the FIDC series with the greatest outstanding share count.
    if (!previous || kind === 'fif' || shares >= previous.shares)
      rows.set(day, { price, shares });
  }
  return {
    push(text: string, final = false) {
      const lines = (tail + text).split('\n');
      tail = lines.pop() ?? '';
      lines.forEach(line);
      if (final && tail) {
        line(tail);
        tail = '';
      }
    },
    result(): FundHistories {
      return Object.fromEntries(
        [...points].map(([id, rows]) => {
          const days = [...rows.keys()].sort((a, b) => a - b);
          return [
            id,
            { days, prices: days.map((day) => rows.get(day)!.price) },
          ];
        }),
      );
    },
  };
}

export async function parseQuotaArchive(
  bytes: Uint8Array,
  kind: FundReportKind,
  month: number,
  ids: Set<string>,
): Promise<FundHistories> {
  const parser = createQuotaParser(kind, ids);
  const filename =
    kind === 'fif'
      ? `inf_diario_fi_${month}.csv`
      : `inf_mensal_fidc_tab_X_2_${month}.csv`;
  let found = false,
    failure: Error | undefined;
  const unzip = new Unzip((file) => {
    if (file.name.split('/').at(-1)?.toLowerCase() !== filename.toLowerCase())
      return;
    found = true;
    file.ondata = (error, data, final) => {
      if (error) {
        failure = error;
        return;
      }
      // Bounded conversion avoids argument limits and doesn't require a native text decoder.
      let text = '';
      for (let offset = 0; offset < data.length; offset += 8192)
        text += String.fromCharCode(...data.subarray(offset, offset + 8192));
      parser.push(text, final);
    };
    file.start();
  });
  unzip.register(UnzipInflate);
  for (let offset = 0; offset < bytes.length; offset += 65536) {
    unzip.push(
      bytes.subarray(offset, offset + 65536),
      offset + 65536 >= bytes.length,
    );
    if (failure) throw failure;
    // Yield between compressed chunks to keep scrolling responsive during large FIF reports.
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
  }
  if (!found) throw new Error('CVM quota table missing');
  return parser.result();
}

export async function fetchQuotaReport(
  kind: FundReportKind,
  month: number,
  ids: Set<string>,
): Promise<FundHistories> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45000);
  const path =
    kind === 'fif'
      ? `FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_${month}`
      : `FIDC/DOC/INF_MENSAL/DADOS/inf_mensal_fidc_${month}`;
  try {
    const response = await fetch(`https://dados.cvm.gov.br/dados/${path}.zip`, {
      signal: controller.signal,
      cache: 'no-store',
    });
    if (response.status === 404) return {}; // A reporting period may not have been published yet.
    if (!response.ok) throw new Error(`CVM HTTP ${response.status}`);
    return await parseQuotaArchive(
      new Uint8Array(await response.arrayBuffer()),
      kind,
      month,
      ids,
    );
  } finally {
    clearTimeout(timeout);
  }
}

export function mergeFundHistories(...sources: FundHistories[]): FundHistories {
  const merged: Record<string, Map<number, number>> = {};
  for (const source of sources)
    for (const [id, history] of Object.entries(source)) {
      const prices = (merged[id] ??= new Map());
      history.days.forEach((day, index) =>
        prices.set(day, history.prices[index]),
      );
    }
  return Object.fromEntries(
    Object.entries(merged).map(([id, prices]) => {
      const days = [...prices.keys()].sort((a, b) => a - b);
      return [id, { days, prices: days.map((day) => prices.get(day)!) }];
    }),
  );
}
