import { SymbolView } from 'expo-symbols';
import { Children, Fragment, isValidElement, useState, type ReactNode } from 'react';
import { Keyboard, Linking, Pressable, StyleSheet, Text, View, type LayoutChangeEvent } from 'react-native';
import Animated, { Easing, ReduceMotion, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

const disclosureAnimation = {
  duration: 240,
  easing: Easing.out(Easing.cubic),
  reduceMotion: ReduceMotion.System,
};

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
  const contentHeight = useSharedValue(0);
  const arrowStyle = useAnimatedStyle(() => ({
    transform: [{ rotate: withTiming(isExpanded ? '90deg' : '0deg', disclosureAnimation) }],
  }));
  const contentStyle = useAnimatedStyle(() => ({
    height: withTiming(isExpanded ? contentHeight.get() : 0, disclosureAnimation),
    opacity: withTiming(isExpanded ? 1 : 0, disclosureAnimation),
  }));

  function toggleExpanded() {
    if (isExpanded) Keyboard.dismiss();
    setIsExpanded((expanded) => !expanded);
  }

  function measureContent(event: LayoutChangeEvent) {
    contentHeight.set(event.nativeEvent.layout.height);
  }

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
    <View>
      {isCollapsible ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={title}
          accessibilityValue={{ text: summary }}
          accessibilityState={{ expanded: isExpanded }}
          onPress={toggleExpanded}
          style={({ pressed }) => [styles.disclosure, { backgroundColor: theme.surface }, pressed && styles.pressed]}>
          <View style={styles.disclosureText}>
            {titleLabel}
            <Text style={[settingsStyles.caption, { color: theme.textSecondary }]}>{summary}</Text>
          </View>
          <Animated.View style={arrowStyle}>
            <SymbolView
              name={{ ios: 'chevron.right', android: 'chevron_right' }}
              size={18}
              tintColor={theme.textSecondary}
            />
          </Animated.View>
        </Pressable>
      ) : titleLabel}
      <Animated.View
        accessibilityElementsHidden={!showContent}
        importantForAccessibility={showContent ? 'auto' : 'no-hide-descendants'}
        pointerEvents={showContent ? 'auto' : 'none'}
        style={isCollapsible ? [styles.contentClip, contentStyle] : undefined}>
        {/* Keep form fields mounted so collapsing preserves unfinished edits. */}
        <View onLayout={measureContent} style={[styles.content, isCollapsible && styles.measuredContent]}>
          <View style={[styles.card, { backgroundColor: theme.surface }]}>{rows}</View>
          <Text style={[styles.footer, { color: theme.textSecondary }]}>{footer}</Text>
        </View>
      </Animated.View>
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
  content: {
    paddingTop: Spacing.two,
    gap: Spacing.two,
  },
  contentClip: {
    overflow: 'hidden',
  },
  measuredContent: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
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
