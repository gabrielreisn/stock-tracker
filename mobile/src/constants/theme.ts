/** Light and dark palettes, matching the website's background and foreground. */
export const Colors = {
  light: {
    background: '#ffffff',
    surface: '#f2f2f4',
    selected: '#e4e4e7',
    text: '#171717',
    textSecondary: '#63636b',
  },
  dark: {
    background: '#0a0a0a',
    surface: '#1a1a1c',
    selected: '#2a2a2e',
    text: '#ededed',
    textSecondary: '#a1a1aa',
  },
} as const;

export const Spacing = {
  one: 4,
  two: 8,
  three: 16,
  four: 24,
} as const;
