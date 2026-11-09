/** Light and dark palettes, matching the website's background and foreground. */
export const Colors = {
  light: {
    background: '#ffffff',
    surface: '#f2f2f4',
    selected: '#e4e4e7',
    text: '#171717',
    textSecondary: '#63636b',
    accent: '#2563eb',
    onAccent: '#ffffff',
    link: '#2563eb',
    success: '#16a34a',
    warning: '#b45309',
    // Same as the chart's series on macOS, so a benchmark keeps its color everywhere.
    benchmarks: {
      cdi: '#eb6834',
      ipca: '#1baf7a',
      sp500: '#eda100',
      ipcaPlus6: '#e87ba4',
      ifix: '#008300',
      ibov: '#7e4fd6',
    },
  },
  dark: {
    background: '#0a0a0a',
    surface: '#1a1a1c',
    selected: '#2a2a2e',
    text: '#ededed',
    textSecondary: '#a1a1aa',
    accent: '#2563eb',
    onAccent: '#ffffff',
    link: '#60a5fa',
    success: '#22c55e',
    warning: '#fb923c',
    benchmarks: {
      cdi: '#d95926',
      ipca: '#199e70',
      sp500: '#c98500',
      ipcaPlus6: '#d55181',
      ifix: '#008300',
      ibov: '#9a6fe8',
    },
  },
} as const;

export const Spacing = {
  one: 4,
  two: 8,
  three: 16,
  four: 24,
} as const;
