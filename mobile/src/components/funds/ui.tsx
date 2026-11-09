import { Text, View } from 'react-native';
import { signedPercent } from '@/lib/fund-performance';
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

export function ReturnMetric({
  label,
  value,
}: {
  label: string;
  value?: number;
}) {
  const theme = useTheme();
  const color =
    value === undefined || value === 0
      ? theme.text
      : value > 0
        ? theme.success
        : '#ef4444';
  return (
    <View style={styles.metric}>
      <Text style={[styles.caption, { color: theme.textSecondary }]}>
        {label}
      </Text>
      <Text style={[styles.value, { color }]}>{signedPercent(value)}</Text>
    </View>
  );
}
