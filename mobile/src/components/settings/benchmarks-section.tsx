import { StyleSheet, Switch, Text, View } from 'react-native';

import { settingsStyles, SettingsGroup } from '@/components/settings/ui';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { BENCHMARKS, MAX_BENCHMARKS, setBenchmark, useEnabledBenchmarks } from '@/lib/benchmarks';
import { t } from '@/lib/i18n';

function Swatch({ color, isDashed }: { color: string; isDashed: boolean }) {
  const segment = [styles.swatchSegment, { backgroundColor: color }];

  return (
    <View style={styles.swatch}>
      <View style={segment} />
      {isDashed && <View style={segment} />}
    </View>
  );
}

export function BenchmarksSection() {
  const theme = useTheme();
  const enabled = useEnabledBenchmarks();

  const summary = BENCHMARKS.filter((benchmark) => enabled.includes(benchmark.id))
    .map((benchmark) => benchmark.label)
    .join(' · ') || t('No benchmarks selected');
  const rows = BENCHMARKS.map((benchmark) => {
    const isOn = enabled.includes(benchmark.id);
    return (
      <View key={benchmark.id} style={[settingsStyles.row, styles.row]}>
        <Swatch color={theme.benchmarks[benchmark.id]} isDashed={benchmark.isRate} />
        <View style={styles.text}>
          <Text style={[settingsStyles.label, { color: theme.text }]}>{benchmark.label}</Text>
          <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>{t(benchmark.detail)}</Text>
        </View>
        <Switch
          accessibilityLabel={benchmark.label}
          disabled={!isOn && enabled.length >= MAX_BENCHMARKS}
          onValueChange={(value) => setBenchmark(benchmark.id, value)}
          thumbColor={theme.onAccent}
          trackColor={{ true: theme.accent, false: theme.selected }}
          value={isOn}
        />
      </View>
    );
  });

  return (
    <SettingsGroup
      title={t('Benchmarks')}
      summary={summary}
      footer={t('Up to {max} at a time, so every line stays distinguishable. Rate-based ones are drawn dashed.', {
        max: MAX_BENCHMARKS,
      })}>
      {rows}
    </SettingsGroup>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.three,
  },
  swatch: {
    flexDirection: 'row',
    alignSelf: 'flex-start',
    gap: 2,
    width: 14,
    height: 3,
    marginTop: 10,
  },
  swatchSegment: {
    flex: 1,
    height: 3,
    borderRadius: 1.5,
  },
  text: {
    flex: 1,
    gap: 2,
  },
});
