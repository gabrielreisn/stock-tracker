import { useColorScheme } from 'react-native';

import { Colors } from '@/constants/theme';

export function useTheme() {
  return Colors[useColorScheme() === 'dark' ? 'dark' : 'light'];
}
