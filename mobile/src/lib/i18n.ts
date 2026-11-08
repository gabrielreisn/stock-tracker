import { getLocales } from 'expo-localization';

// Same convention as macOS/Resources/pt-BR.lproj/Localizable.strings: the English text is the key.
const portuguese = {
  AI: 'IA',
  Bills: 'Contas',
  Bonds: 'Renda fixa',
  'Categories & limits': 'Limites e categorias',
  'Coming soon': 'Em breve',
  Expenses: 'Compras e entradas',
  'FGC Watcher': 'Monitor do FGC',
  Finances: 'Finanças',
  'Fund Comparison': 'Comparar fundos',
  Funds: 'Fundos',
  Insights: 'Insights',
  Investments: 'Investimentos',
  'Open Finance': 'Open Finance',
  Overview: 'Visão geral',
  Settings: 'Ajustes',
  Stocks: 'Ações',
} as const;

export type StringKey = keyof typeof portuguese;

const isPortuguese = getLocales()[0]?.languageCode === 'pt';

export function t(key: StringKey): string {
  return isPortuguese ? portuguese[key] : key;
}
