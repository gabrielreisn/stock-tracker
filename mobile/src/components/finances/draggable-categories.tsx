import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { Animated, PanResponder, StyleSheet, View, type ScrollViewInstance } from 'react-native';
import { SymbolView } from 'expo-symbols';
import { useTheme } from '@/hooks/use-theme';
import { categoryDropIndex, type CategoryScrollMetrics } from '@/lib/category-order';
import { t } from '@/lib/i18n';
import type { ExpenseCategory } from '@/types';

type Frame = { y: number; height: number };
type Drag = { id: string; initialOffset: number; dy: number; fingerY: number; top: number; bottom: number };
function DragHandle({ name, begin, move, finish, cancel, moveUp, moveDown }: {
  name: string; begin: (pageY: number) => void; move: (dy: number, pageY: number) => void;
  finish: () => void; cancel: () => void; moveUp: () => void; moveDown: () => void;
}) {
  const theme = useTheme();
  const callbacks = useRef({ begin, move, finish, cancel });
  useEffect(function syncDragCallbacks() { callbacks.current = { begin, move, finish, cancel }; }, [begin, move, finish, cancel]);
  // PanResponder retains these callbacks and invokes them only for native touch events.
  // Keep its gesture state stable across the renders that show drag/drop feedback.
  // eslint-disable-next-line react-hooks/refs -- These refs are read by deferred event handlers, never by PanResponder.create.
  const [responder] = useState(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onPanResponderGrant: event => callbacks.current.begin(event.nativeEvent.pageY),
    onPanResponderMove: (_, gesture) => callbacks.current.move(gesture.dy, gesture.moveY),
    onPanResponderRelease: () => callbacks.current.finish(),
    onPanResponderTerminate: () => callbacks.current.cancel(),
    onPanResponderTerminationRequest: () => false,
  }));
  return (
    <View {...responder.panHandlers} accessible accessibilityRole="adjustable"
      accessibilityLabel={t('Reorder {name}', { name })} accessibilityHint={t('Drag to reorder, or use accessibility actions.')}
      accessibilityActions={[{ name: 'increment', label: t('Move down') }, { name: 'decrement', label: t('Move up') }]}
      onAccessibilityAction={event => event.nativeEvent.actionName === 'increment' ? moveDown() : moveUp()} style={styles.handle}>
      <SymbolView name={{ ios: 'line.3.horizontal', android: 'drag_handle', web: 'drag_handle' }} size={24} tintColor={theme.textSecondary} />
    </View>
  );
}

/** Native responder drag handles keep taps for editing and scrolling outside the handle. */
export function DraggableCategories({ categories, renderCategory, categoryName, onReorder, scrollRef, metrics, onDragging }: {
  categories: ExpenseCategory[]; renderCategory: (category: ExpenseCategory) => ReactNode;
  categoryName: (name: string) => string; onReorder: (id: string, destination: number) => void;
  scrollRef: RefObject<ScrollViewInstance | null>; metrics: RefObject<CategoryScrollMetrics>; onDragging: (active: boolean) => void;
}) {
  const theme = useTheme();
  const frames = useRef(new Map<string, Frame>());
  const drag = useRef<Drag | null>(null);
  const [active, setActive] = useState<string | null>(null);
  const [target, setTarget] = useState<string | null>(null);
  const [translation] = useState(() => new Animated.Value(0));
  function updatePosition() {
    const current = drag.current;
    if (!current) return;
    const delta = current.dy + metrics.current.offset - current.initialOffset;
    translation.setValue(delta);
    const frame = frames.current.get(current.id);
    const layout = categories.map(category => frames.current.get(category.id) ?? { y: 0, height: 0 });
    if (frame) setTarget(categories[categoryDropIndex(layout, frame.y + frame.height / 2 + delta)]?.id ?? null);
  }
  function begin(id: string, pageY: number) {
    drag.current = { id, initialOffset: metrics.current.offset, dy: 0, fingerY: pageY, top: 0, bottom: 0 };
    translation.setValue(0);
    setActive(id);
    setTarget(id);
    onDragging(true);
    scrollRef.current?.measureInWindow((_x, y, _width, height) => {
      if (drag.current?.id === id) { drag.current.top = y; drag.current.bottom = y + height; }
    });
  }
  function end(commit: boolean) {
    const current = drag.current;
    if (current && commit) {
      const frame = frames.current.get(current.id);
      const layout = categories.map(category => frames.current.get(category.id) ?? { y: 0, height: 0 });
      const delta = current.dy + metrics.current.offset - current.initialOffset;
      if (frame) onReorder(current.id, categoryDropIndex(layout, frame.y + frame.height / 2 + delta));
    }
    drag.current = null;
    translation.setValue(0);
    setActive(null);
    setTarget(null);
    onDragging(false);
  }
  useEffect(function scrollNearEdgesWhileDragging() {
    if (!active) return;
    const timer = setInterval(() => {
      const current = drag.current;
      if (!current?.bottom) return;
      const step = current.fingerY < current.top + 64 ? -8 : current.fingerY > current.bottom - 64 ? 8 : 0;
      const offset = Math.max(0, Math.min(metrics.current.max, metrics.current.offset + step));
      if (offset !== metrics.current.offset) {
        metrics.current.offset = offset;
        scrollRef.current?.scrollTo({ y: offset, animated: false });
        translation.setValue(current.dy + offset - current.initialOffset);
        // Drop calculation reads the latest offset, even while the finger is held still.
        const frame = frames.current.get(current.id);
        const layout = categories.map(category => frames.current.get(category.id) ?? { y: 0, height: 0 });
        if (frame) setTarget(categories[categoryDropIndex(layout, frame.y + frame.height / 2 + current.dy + offset - current.initialOffset)]?.id ?? null);
      }
    }, 16);
    return () => clearInterval(timer);
  }, [active, categories, metrics, scrollRef, translation]);
  const rows = categories.map((category, index) => {
    const dragging = active === category.id;
    const destination = target === category.id && !dragging;
    return (
      <Animated.View key={category.id} onLayout={event => frames.current.set(category.id, event.nativeEvent.layout)}
        style={[styles.row, { backgroundColor: dragging ? theme.selected : theme.surface },
          index === 0 && styles.firstRow, index === categories.length - 1 && styles.lastRow,
          dragging && styles.dragging, dragging && { transform: [{ translateY: translation }] }]}>
        {renderCategory(category)}
        <DragHandle name={categoryName(category.name)} begin={pageY => begin(category.id, pageY)}
          move={(dy, pageY) => { if (drag.current) { drag.current.dy = dy; drag.current.fingerY = pageY; updatePosition(); } }}
          finish={() => end(true)} cancel={() => end(false)}
          moveUp={() => onReorder(category.id, index - 1)} moveDown={() => onReorder(category.id, index + 1)} />
        {index < categories.length - 1 && <View pointerEvents="none"
          style={[styles.separator, { backgroundColor: destination ? theme.link : theme.selected }]} />}
      </Animated.View>
    );
  });
  return <View style={styles.list}>{rows}</View>;
}
const styles = StyleSheet.create({
  list: { borderRadius: 12 },
  row: { flexDirection: 'row', alignItems: 'center', paddingLeft: 12 },
  firstRow: { borderTopLeftRadius: 12, borderTopRightRadius: 12 },
  lastRow: { borderBottomLeftRadius: 12, borderBottomRightRadius: 12 },
  separator: { position: 'absolute', left: 58, right: 12, bottom: 0, height: 1 },
  handle: { width: 44, minHeight: 44, flexShrink: 0, alignSelf: 'stretch', justifyContent: 'center', alignItems: 'center' },
  dragging: { zIndex: 10, borderRadius: 12 },
});
