import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { AccessibilityInfo, Animated, PanResponder, StyleSheet, View, type LayoutChangeEvent, type ScrollViewInstance } from 'react-native';
import { SymbolView } from 'expo-symbols';
import { useTheme } from '@/hooks/use-theme';
import { categoryDragOffsets, categoryDropIndex, type CategoryFrame, type CategoryScrollMetrics } from '@/lib/category-order';
import { t } from '@/lib/i18n';
import type { ExpenseCategory } from '@/types';

type Frame = { y: number; height: number };
type Drag = { id: string; initialOffset: number; dy: number; fingerY: number; top: number; bottom: number; settling: boolean; frames: CategoryFrame[] };
const rowSpring = { stiffness: 320, damping: 32, mass: 0.8, overshootClamping: true, useNativeDriver: true };

function AnimatedCategoryRow({ id, index, last, active, offset, translation, reduceMotion, onLayout, children }: {
  id: string; index: number; last: boolean; active: boolean; offset: number; translation: Animated.Value;
  reduceMotion: boolean; onLayout: (id: string, event: LayoutChangeEvent) => void; children: ReactNode;
}) {
  const theme = useTheme();
  const [shift] = useState(() => new Animated.Value(0));
  // The new layout is already at the preview position when the persisted order changes.
  // Reset its temporary transform in the same commit so there is no second visual move.
  useLayoutEffect(function resetPreviewAfterReorder() {
    shift.stopAnimation();
    shift.setValue(0);
  }, [index, shift]);
  useEffect(function animateSpaceForDraggedRow() {
    if (active) { shift.setValue(0); return; }
    if (reduceMotion) { shift.setValue(offset); return; }
    const animation = Animated.spring(shift, { ...rowSpring, toValue: offset });
    animation.start();
    return () => animation.stop();
  }, [active, index, offset, reduceMotion, shift]);
  return (
    <Animated.View onLayout={event => onLayout(id, event)}
      style={[styles.row, { backgroundColor: active ? theme.selected : theme.surface },
        index === 0 && styles.firstRow, last && styles.lastRow, active && styles.dragging,
        { transform: [{ translateY: active ? translation : shift }] }]}>
      {children}
    </Animated.View>
  );
}
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
  const [target, setTarget] = useState(0);
  const [dragFrames, setDragFrames] = useState<CategoryFrame[]>([]);
  const [reduceMotion, setReduceMotion] = useState(false);
  const [translation] = useState(() => new Animated.Value(0));
  useEffect(function followReducedMotionPreference() {
    let mounted = true;
    void AccessibilityInfo.isReduceMotionEnabled().then(value => { if (mounted) setReduceMotion(value); });
    const listener = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => { mounted = false; listener.remove(); };
  }, []);
  useEffect(function stopAnimationOnUnmount() { return () => translation.stopAnimation(); }, [translation]);
  function updatePosition() {
    const current = drag.current;
    if (!current || current.settling) return;
    const delta = current.dy + metrics.current.offset - current.initialOffset;
    translation.setValue(delta);
    const frame = current.frames.find(row => row.id === current.id);
    if (frame) setTarget(categoryDropIndex(current.frames, frame.y + frame.height / 2 + delta));
  }
  function begin(id: string, pageY: number) {
    if (drag.current) return;
    const layout = categories.map(category => ({ id: category.id, ...frames.current.get(category.id)! }));
    if (layout.some(frame => !frame.height)) return;
    drag.current = { id, initialOffset: metrics.current.offset, dy: 0, fingerY: pageY, top: 0, bottom: 0, settling: false, frames: layout };
    translation.stopAnimation();
    translation.setValue(0);
    setDragFrames(layout);
    setActive(id);
    setTarget(categories.findIndex(category => category.id === id));
    onDragging(true);
    scrollRef.current?.measureInWindow((_x, y, _width, height) => {
      if (drag.current?.id === id) { drag.current.top = y; drag.current.bottom = y + height; }
    });
  }
  function end(commit: boolean) {
    const current = drag.current;
    if (!current || current.settling) return;
    const frame = current.frames.find(row => row.id === current.id);
    if (!frame) return;
    current.settling = true;
    const delta = current.dy + metrics.current.offset - current.initialOffset;
    const destination = commit ? categoryDropIndex(current.frames, frame.y + frame.height / 2 + delta)
      : current.frames.findIndex(row => row.id === current.id);
    setTarget(destination);
    const offsets = categoryDragOffsets(current.frames, current.id, destination);
    const id = current.id;
    function finish() {
      if (commit) onReorder(id, destination);
      drag.current = null;
      setActive(null);
      onDragging(false);
      // Keep translation at its settled position until the layout and active row change together.
      // The next drag resets it before following the finger.
    }
    if (reduceMotion) { finish(); return; }
    Animated.spring(translation, { ...rowSpring, toValue: offsets[current.id] ?? 0 }).start(({ finished }) => {
      if (finished) finish();
    });
  }
  useEffect(function scrollNearEdgesWhileDragging() {
    if (!active) return;
    const timer = setInterval(() => {
      const current = drag.current;
      if (!current?.bottom || current.settling) return;
      const step = current.fingerY < current.top + 64 ? -8 : current.fingerY > current.bottom - 64 ? 8 : 0;
      const offset = Math.max(0, Math.min(metrics.current.max, metrics.current.offset + step));
      if (offset !== metrics.current.offset) {
        metrics.current.offset = offset;
        scrollRef.current?.scrollTo({ y: offset, animated: false });
        translation.setValue(current.dy + offset - current.initialOffset);
        // Drop calculation reads the latest offset, even while the finger is held still.
        const frame = current.frames.find(row => row.id === current.id);
        if (frame) setTarget(categoryDropIndex(current.frames, frame.y + frame.height / 2 + current.dy + offset - current.initialOffset));
      }
    }, 16);
    return () => clearInterval(timer);
  }, [active, categories, metrics, scrollRef, translation]);
  const offsets = active ? categoryDragOffsets(dragFrames, active, target) : {};
  const rows = categories.map((category, index) => {
    const dragging = active === category.id;
    return (
      <AnimatedCategoryRow key={category.id} id={category.id} index={index} last={index === categories.length - 1}
        active={dragging} offset={offsets[category.id] ?? 0} translation={translation} reduceMotion={reduceMotion}
        onLayout={(id, event) => frames.current.set(id, event.nativeEvent.layout)}>
        {renderCategory(category)}
        <DragHandle name={categoryName(category.name)} begin={pageY => begin(category.id, pageY)}
          move={(dy, pageY) => { if (drag.current && !drag.current.settling) { drag.current.dy = dy; drag.current.fingerY = pageY; updatePosition(); } }}
          finish={() => end(true)} cancel={() => end(false)}
          moveUp={() => onReorder(category.id, index - 1)} moveDown={() => onReorder(category.id, index + 1)} />
        {index < categories.length - 1 && <View pointerEvents="none"
          style={[styles.separator, { backgroundColor: theme.selected }]} />}
      </AnimatedCategoryRow>
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
