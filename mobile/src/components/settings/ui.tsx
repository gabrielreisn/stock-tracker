import { SymbolView } from 'expo-symbols';
import { Children, Fragment, isValidElement, useState, type ReactNode } from 'react';
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';

import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

export function SettingsGroup({
  title,
  footer,
  summary,
  children,
}: {
  title: string;
  footer: string;
  summary?: string;
  children: ReactNode;
}) {
  const theme = useTheme();
  const [isExpanded, setIsExpanded] = useState(false);
  const isCollapsible = summary !== undefined;
  const showContent = !isCollapsible || isExpanded;
  const rows = Children.toArray(children).map((child, index) => (
    <Fragment key={isValidElement(child) ? child.key : String(child)}>
      {index > 0 && <View style={[styles.separator, { backgroundColor: theme.selected }]} />}
      {child}
    </Fragment>
  ));
  const titleLabel = (
    <Text accessibilityRole="header" style={[styles.groupTitle, { color: theme.text }]}>
      {title}
    </Text>
  );

  return (
    <View style={styles.group}>
      {isCollapsible ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={title}
          accessibilityValue={{ text: summary }}
          accessibilityState={{ expanded: isExpanded }}
          onPress={() => setIsExpanded((expanded) => !expanded)}
          style={({ pressed }) => [styles.disclosure, { backgroundColor: theme.surface }, pressed && styles.pressed]}>
          <View style={styles.disclosureText}>
            {titleLabel}
            <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>{summary}</Text>
          </View>
          <SymbolView
            name={isExpanded ? { ios: 'chevron.down', android: 'expand_more' } : { ios: 'chevron.right', android: 'chevron_right' }}
            size={18}
            tintColor={theme.textSecondary}
          />
        </Pressable>
      ) : titleLabel}
      {showContent && (
        <>
          <View style={[styles.card, { backgroundColor: theme.surface }]}>{rows}</View>
          <Text style={[styles.footer, { color: theme.textSecondary }]}>{footer}</Text>
        </>
      )}
    </View>
  );
}

export function ActionButton({
  title,
  onPress,
  isPrimary = false,
  isDisabled = false,
  accessibilityLabel,
}: {
  title: string;
  onPress: () => void;
  isPrimary?: boolean;
  isDisabled?: boolean;
  accessibilityLabel?: string;
}) {
  const theme = useTheme();

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
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
  disclosure: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.three,
    padding: Spacing.three,
    borderRadius: 12,
    minHeight: 64,
  },
  disclosureText: {
    flex: 1,
    gap: Spacing.one,
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
