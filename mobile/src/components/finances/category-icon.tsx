import { SymbolView } from 'expo-symbols';
import { categoryIcons } from '@/lib/category-icons';

export function CategoryIcon({ symbol, color }: { symbol: string; color: string }) {
  const [ios, android] = categoryIcons.find(([name]) => name === symbol) ?? categoryIcons[15];
  return <SymbolView name={{ ios, android, web: android }} tintColor={color} size={22} />;
}
