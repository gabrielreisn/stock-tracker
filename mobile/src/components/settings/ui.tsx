import { Children, Fragment, isValidElement, type ReactNode } from 'react';
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';

import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

export function SettingsGroup({
  title,
  footer,
  children,
}: {
  title: string;
  footer: string;
  children: ReactNode;
}) {
  const theme = useTheme();

  return (
    <View style={styles.group}>
      <Text accessibilityRole="header" style={[styles.groupTitle, { color: theme.text }]}>
        {title}
      </Text>
      <View style={[styles.card, { backgroundColor: theme.surface }]}>
        {Children.toArray(children).map((child, index) => (
          <Fragment key={isValidElement(child) ? child.key : String(child)}>
            {index > 0 && <View style={[styles.separator, { backgroundColor: theme.selected }]} />}
            {child}
          </Fragment>
        ))}
      </View>
      <Text style={[styles.footer, { color: theme.textSecondary }]}>{footer}</Text>
    </View>
  );
}

export function ActionButton({
  title,
  onPress,
  isPrimary = false,
  isDisabled = false,
}: {
  title: string;
  onPress: () => void;
  isPrimary?: boolean;
  isDisabled?: boolean;
}) {
  const theme = useTheme();

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: isDisabled }}
      disabled={isDisabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: isPrimary ? theme.accent : theme.selected },
        isDisabled && styles.disabled,
        pressed && styles.pressed,
      ]}>
      <Text style={[styles.buttonLabel, { color: isPrimary ? theme.onAccent : theme.text }]}>{title}</Text>
    </Pressable>
  );
}

/** Turns `[label](https://…)` in a translated string into tappable text. */
export function LinkedText({ text, style }: { text: string; style: object }) {
  const theme = useTheme();
  const parts = text.split(/\[([^\]]+)\]\((https:[^)]+)\)/);

  return (
    <Text style={style}>
      {parts.map((part, index) => {
        // split() with two capture groups repeats as: plain text, label, url.
        if (index % 3 === 0) return part;
        if (index % 3 === 2) return null;
        const url = parts[index + 1];
        return (
          <Text
            key={url}
            accessibilityRole="link"
            onPress={() => void Linking.openURL(url)}
            style={{ color: theme.link }}>
            {part}
          </Text>
        );
      })}
    </Text>
  );
}

export const settingsStyles = StyleSheet.create({
  row: {
    padding: Spacing.three,
    gap: Spacing.two,
  },
  label: {
    fontSize: 16,
  },
  caption: {
    fontSize: 13,
    lineHeight: 18,
  },
});

const styles = StyleSheet.create({
  group: {
    gap: Spacing.two,
  },
  groupTitle: {
    fontSize: 20,
    fontWeight: '600',
  },
  card: {
    borderRadius: 12,
    overflow: 'hidden',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: Spacing.three,
  },
  footer: {
    fontSize: 13,
    lineHeight: 18,
    paddingHorizontal: Spacing.one,
  },
  button: {
    minHeight: 44,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: Spacing.three,
  },
  buttonLabel: {
    fontSize: 16,
    fontWeight: '600',
  },
  disabled: {
    opacity: 0.4,
  },
  pressed: {
    opacity: 0.7,
  },
});
