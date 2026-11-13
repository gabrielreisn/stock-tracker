import { router } from 'expo-router';
import { useEffect, useRef, useState, type ComponentRef } from 'react';
import { KeyboardAvoidingView, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import { CategoryIcon } from '@/components/finances/category-icon';
import { OpenFinanceSection } from '@/components/settings/open-finance-section';
import { ActionButton, LinkedText } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { expenseStore } from '@/lib/account-store';
import { t, type StringKey } from '@/lib/i18n';
import {
  adoptOnboardingCategories, hasStartingCategories, markOnboardingSeen,
  onboardingCategories, shouldShowOnboarding,
} from '@/lib/onboarding';
import { usePluggy } from '@/lib/pluggy-store';

const steps = [
  { title: 'Welcome to Cymba', message: 'Your stocks, bonds, funds and spending in one place, checked against CDI, IPCA and the market. A few quick steps and you’re set.' },
  { title: 'Create your Meu Pluggy account', message: 'Meu Pluggy is a free service that reaches your banks and brokers through Open Finance. Create an account and connect your banks and brokers there; Cymba reads them from it.' },
  { title: 'Get your Client ID and secret', message: 'In the Pluggy dashboard, open your application and copy its Client ID and Client Secret. You’ll paste them in the next step.' },
  { title: 'Sync with Open Finance', message: 'Paste the Client ID and secret, then connect each bank or broker. Each connection shares one institution from Meu Pluggy; connect again for the next one.' },
  { title: 'What do you spend on?', message: 'Pick the kinds of expenses you have. Transactions from your banks are sorted into them, and you can set a monthly limit for each in Categories & limits.' },
  { title: 'You’re all set', message: 'Before relying on the numbers, review everything Open Finance brought in on the Open Finance page: the positions it found, how they were matched to what Cymba tracks, and their average prices.' },
] as const;

function SetupGuide({ onFinish }: { onFinish: (review: boolean) => void }) {
  const theme = useTheme();
  const pluggy = usePluggy();
  const [step, setStep] = useState(0);
  const [reached, setReached] = useState(0);
  const [picked, setPicked] = useState(() => new Set<string>());
  const scroll = useRef<ComponentRef<typeof ScrollView>>(null);
  const page = steps[step];
  const connected = pluggy.itemIDs.length > 0;
  const blocked = step === 3 && !connected;
  const { settings } = expenseStore.useValue();
  const locked = new Set(hasStartingCategories(settings) ? [] : settings.categories.map(category => category.id));

  function go(target: number) {
    if (target > 3 && !connected) return;
    setStep(target);
    setReached(previous => Math.max(previous, target));
    scroll.current?.scrollTo({ y: 0, animated: false });
  }

  function finish(review = false) {
    if (step === 5) {
      expenseStore.set({ settings: adoptOnboardingCategories(expenseStore.get().settings, picked) });
    }
    onFinish(review);
  }

  const progress = steps.map((item, index) => (
    <Pressable key={item.title} accessibilityRole="button" accessibilityLabel={t(item.title)}
      accessibilityState={{ selected: index === step, disabled: index > reached }}
      disabled={index > reached} onPress={() => go(index)}
      style={[styles.dot, { backgroundColor: index === step ? theme.accent : theme.selected }]}>
      <Text style={{ color: index === step ? theme.onAccent : theme.textSecondary }}>{index < step ? '✓' : index + 1}</Text>
    </Pressable>
  ));
  const categoryTiles = onboardingCategories.map(category => {
    const isLocked = locked.has(category.id);
    const selected = picked.has(category.id) || isLocked;
    return (
      <Pressable key={category.id} accessibilityRole="checkbox" accessibilityState={{ checked: selected, disabled: isLocked }}
        disabled={isLocked} onPress={() => setPicked(previous => {
          const next = new Set(previous);
          if (next.has(category.id)) next.delete(category.id); else next.add(category.id);
          return next;
        })}
        style={[styles.tile, { borderColor: selected ? theme.accent : theme.selected, backgroundColor: theme.surface }]}>
        <CategoryIcon symbol={category.symbol} color={selected ? theme.accent : theme.textSecondary} />
        <Text style={[styles.category, { color: theme.text }]}>{t(category.name as StringKey)}</Text>
        {selected && <Text style={{ color: theme.accent }}>✓</Text>}
      </Pressable>
    );
  });

  return (
    <SafeAreaView style={[styles.root, { backgroundColor: theme.background }]}>
      <KeyboardAvoidingView behavior="padding" style={styles.root}>
        <View style={styles.progress}>{progress}</View>
        <ScrollView ref={scroll} contentContainerStyle={styles.content} keyboardDismissMode="on-drag" keyboardShouldPersistTaps="handled">
          <Text style={[styles.counter, { color: theme.textSecondary }]}>{t('Step {step} of {count}', { step: step + 1, count: steps.length })}</Text>
          <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>{t(page.title)}</Text>
          <Text style={[styles.message, { color: theme.textSecondary }]}>{t(page.message)}</Text>
          {step === 1 && <LinkedText text={t('[Open meu.pluggy.ai](https://meu.pluggy.ai)')} style={styles.message} />}
          {step === 2 && <LinkedText text={t('[Open the Pluggy dashboard](https://dashboard.pluggy.ai)')} style={styles.message} />}
          {step === 3 && <OpenFinanceSection inOnboarding />}
          {step === 4 && <View style={styles.grid}>{categoryTiles}</View>}
          {step === 5 && <ActionButton title={t('Review on the Open Finance page')} onPress={() => finish(true)} isPrimary />}
        </ScrollView>
        <View style={[styles.footer, { borderColor: theme.selected }]}>
          {blocked && <Text style={[styles.hint, { color: theme.textSecondary }]}>{t('Connect at least one bank or broker to continue')}</Text>}
          <View style={styles.actions}>
            {step > 0 && <ActionButton title={t('Back')} onPress={() => go(step - 1)} />}
            <View style={styles.next}>
              <ActionButton title={t(step === 5 ? 'Finish' : step === 0 ? 'Get started' : 'Continue')}
                onPress={() => step === 5 ? finish() : go(step + 1)} isDisabled={blocked} isPrimary />
            </View>
          </View>
          {step !== 5 && <ActionButton title={t('Skip setup')} onPress={() => finish()} />}
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

/** The modal covers every tab/deep link on first launch. No route/history entry can reopen it. */
export function Onboarding() {
  const [visible, setVisible] = useState(shouldShowOnboarding);

  useEffect(function recordFirstLaunch() {
    // Record immediately, including legacy installations. An interrupted guide must not return on updates.
    markOnboardingSeen();
  }, []);

  function finish(review: boolean) {
    setVisible(false);
    if (review) router.navigate('/finances/open-finance');
  }

  if (!visible) return null;
  return (
    <Modal visible animationType="slide" presentationStyle="fullScreen" onRequestClose={() => finish(false)}>
      <SafeAreaProvider>
        <SetupGuide onFinish={finish} />
      </SafeAreaProvider>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  progress: { flexDirection: 'row', justifyContent: 'center', gap: 4, padding: 16 },
  dot: { minWidth: 44, minHeight: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  content: { padding: 24, gap: 20 },
  counter: { fontSize: 13 },
  title: { fontSize: 30, fontWeight: '700' },
  message: { fontSize: 16, lineHeight: 24 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  tile: { width: '47%', minHeight: 110, borderRadius: 14, borderWidth: 1.5, padding: 12, gap: 8, alignItems: 'center', justifyContent: 'center' },
  category: { fontSize: 13, textAlign: 'center' },
  footer: { borderTopWidth: StyleSheet.hairlineWidth, padding: 16, gap: 12 },
  hint: { fontSize: 13, textAlign: 'center' },
  actions: { flexDirection: 'row', gap: 12 },
  next: { flex: 1 },
});
