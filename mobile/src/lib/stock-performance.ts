import { BENCHMARKS } from '@/lib/benchmarks';
import type { BondRates } from '@/lib/bonds';
import { inReais } from '@/lib/stocks';
import type { BenchmarkId } from '@/types';
import type { StockPoint, StockQuote } from '@/types/stocks';

export const percent = (value?: number) => value === undefined ? '—' : `${value >= 0 ? '+' : ''}${(value * 100).toFixed(2)}%`;
export function performanceSeries(portfolio: StockPoint[], quotes: Record<string, StockQuote>, rates: BondRates | null, start: number, enabled: BenchmarkId[], colors: { accent: string; benchmarks: Record<BenchmarkId, string> }, portfolioLabel: string) {
  const enabledSet = new Set(enabled);
  const series: { id: string; label: string; color: string; points: StockPoint[]; dashed: boolean }[] = [{ id: 'portfolio', label: portfolioLabel, color: colors.accent, points: portfolio, dashed: false }];
  const missing: string[] = [];
  for (const benchmark of BENCHMARKS.filter(b => enabledSet.has(b.id))) {
    let points: StockPoint[] = [];
    if (benchmark.isRate && rates && portfolio.length) {
      const source = benchmark.id === 'cdi' ? rates.cdi : rates.ipca;
      if (source.length) {
        let factor = 1, cursor = 0;
        const baseDay = portfolio[0].day;
        // Monthly inflation is applied on publication-month boundaries; never projected.
        points = portfolio.map(point => {
          while (cursor < source.length && source[cursor].day <= point.day) {
            if (source[cursor].day > baseDay) factor *= 1 + source[cursor].rate / 100;
            cursor++;
          }
          const date = new Date(`${String(point.day).slice(0, 4)}-${String(point.day).slice(4, 6)}-${String(point.day).slice(6)}T12:00:00Z`);
          const base = new Date(`${String(baseDay).slice(0, 4)}-${String(baseDay).slice(4, 6)}-${String(baseDay).slice(6)}T12:00:00Z`);
          const real = benchmark.id === 'ipcaPlus6' ? Math.pow(1.06, (date.getTime() - base.getTime()) / 86400000 / 365.25) : 1;
          return { day: point.day, value: factor * real - 1 };
        });
      }
    } else {
      const symbol = benchmark.id === 'sp500' ? '^SP500TR' : benchmark.id === 'ibov' ? '^BVSP' : undefined;
      const history = symbol === '^SP500TR' ? inReais('SPY', quotes[symbol], quotes['BRL=X']) : symbol ? quotes[symbol]?.history : undefined;
      if (history) {
        const first = history.days.findIndex(day => day >= start);
        const offset = Math.max(0, first - 1), base = history.prices[offset];
        if (first >= 0 && base) points = history.days.slice(offset).map((day, index) => ({ day, value: history.prices[offset + index] / base - 1 }));
      }
    }
    if (points.length) series.push({ id: benchmark.id, label: benchmark.label, color: colors.benchmarks[benchmark.id], points, dashed: benchmark.isRate });
    else missing.push(benchmark.label);
  }
  return { series, missing };
}
