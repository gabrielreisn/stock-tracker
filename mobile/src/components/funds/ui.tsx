import { Text, View } from 'react-native';
import { styles } from './styles';
import { useTheme } from '@/hooks/use-theme';

export function Metric({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={styles.metric}>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>
        {label}
      </Text>
      <Text style={[styles.value, { color: theme.text }]}>{value}</Text>
    </View>
  );
}
