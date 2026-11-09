import { useState } from 'react';
import { Alert, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ActionButton, SettingsGroup } from '@/components/settings/ui';
import { useTheme } from '@/hooks/use-theme';
import { accountStore, expenseStore } from '@/lib/account-store';
import { classifyExpenses, deleteCategory, limitStatus, newCategory, parseAmount, spendingByCategory, suggestLimits } from '@/lib/expenses';
import { language, t, type StringKey } from '@/lib/i18n';
import type { ExpenseCategory, ExpenseSettings } from '@/types';
import { CategoryIcon } from './category-icon';
import { categoryIcons } from '@/lib/category-icons';

const numberFormat = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const moneyFormat = new Intl.NumberFormat(language === 'pt' ? 'pt-BR' : 'en-US', { style: 'currency', currency: 'BRL' });
const categoryNames: Record<string, StringKey> = {
  "Groceries & Cleaning": "Groceries & Cleaning",
  "Home & Furniture": "Home & Furniture",
  "Delivery & Restaurants": "Delivery & Restaurants",
  "Transport & Travel": "Transport & Travel",
  "Health & Pharmacy": "Health & Pharmacy",
  "Beauty & Self-care": "Beauty & Self-care",
  "Electronics & Tech": "Electronics & Tech",
  "Subscriptions & Apps": "Subscriptions & Apps",
  "Books & Education": "Books & Education",
  "Pets": "Pets",
  "Clothing & Accessories": "Clothing & Accessories",
  "Leisure & Games": "Leisure & Games",
  "Housing & Bills": "Housing & Bills",
  "PIX & Transfers": "PIX & Transfers",
  "Shopping": "Shopping",
};
function categoryName(name: string) { return categoryNames[name] ? t(categoryNames[name]) : name; }
function amountText(value?: number) { return value === undefined ? '' : numberFormat.format(value); }
function updateSettings(patch: Partial<ExpenseSettings>) {
  expenseStore.set({ settings: { ...expenseStore.get().settings, ...patch } });
}

function AmountField({ label, value, onCommit, placeholder = t('No limit') }: {
  label: string; value?: number; onCommit: (value?: number) => void; placeholder?: string;
}) {
  const theme = useTheme();
  const [draft, setDraft] = useState<string | null>(null);
  const invalid = draft !== null && parseAmount(draft) === 'invalid';
  function commit() {
    if (draft === null) return;
    const parsed = parseAmount(draft);
    if (parsed === 'invalid') return;
    onCommit(parsed);
    setDraft(null);
  }
  return (
    <View style={styles.field}>
      <Text style={[styles.label, { color: theme.text }]}>{label}</Text>
      <TextInput accessibilityLabel={label} value={draft ?? amountText(value)} onChangeText={setDraft}
        onBlur={commit} onSubmitEditing={commit} keyboardType="decimal-pad" placeholder={placeholder}
        placeholderTextColor={theme.textSecondary} style={[styles.input, { color: theme.text, backgroundColor: theme.background }]} />
      {draft !== null && <ActionButton title={t('Save')} onPress={commit} isDisabled={invalid} />}
      {invalid && <Text accessibilityRole="alert" style={{ color: theme.warning }}>{t('Enter a positive amount, like 1.234,50.')}</Text>}
    </View>
  );
}

function Spending({ spent, limit, alertAt }: { spent: number; limit?: number; alertAt: number }) {
  const theme = useTheme();
  const status = limitStatus(spent, limit, alertAt);
  const color = status === 'over' ? '#dc2626' : status === 'warning' ? theme.warning : theme.textSecondary;
  const statusText = status === 'over' ? t('Over limit') : status === 'warning' ? t('Near limit') : '';
  const text = limit ? t('{spent} of {limit}', { spent: moneyFormat.format(spent), limit: moneyFormat.format(limit) }) : moneyFormat.format(spent);
  return (
    <View style={styles.spending}>
      <Text style={[styles.caption, { color }]}>{text}{statusText ? ` · ${statusText}` : ''}</Text>
      {!!limit && <View accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: 100, now: Math.min(100, Math.round(spent / limit * 100)) }}
        style={[styles.track, { backgroundColor: theme.selected }]}>
        <View style={[styles.fill, { backgroundColor: color, width: `${Math.min(100, spent / limit * 100)}%` }]} />
      </View>}
    </View>
  );
}

function CategoryEditor({ category, isNew, onClose }: { category: ExpenseCategory; isNew: boolean; onClose: () => void }) {
  const theme = useTheme();
  const [name, setName] = useState(() => categoryName(category.name));
  const [symbol, setSymbol] = useState(category.symbol);
  const [limit, setLimit] = useState(() => amountText(category.limit));
  const parsed = parseAmount(limit);
  const canSave = !!name.trim() && parsed !== 'invalid';
  function save() {
    if (!canSave) return;
    // Leave fixture names in English until the user actually renames them.
    const saved = { ...category, name: name.trim() === categoryName(category.name) ? category.name : name.trim(), symbol, limit: parsed };
    const categories = expenseStore.get().settings.categories;
    updateSettings({ categories: isNew ? [...categories, saved] : categories.map((item) => item.id === saved.id ? saved : item) });
    onClose();
  }
  function confirmDelete() {
    Alert.alert(t('Delete “{name}”?', { name: categoryName(category.name) }), t('Its purchases go back to “To review”.'), [
      { text: t('Cancel'), style: 'cancel' },
      { text: t('Delete'), style: 'destructive', onPress: () => {
        expenseStore.set({ settings: deleteCategory(expenseStore.get().settings, category.id) });
        onClose();
      } },
    ]);
  }
  const icons = categoryIcons.map(([sf, md]) => (
    <Pressable key={sf} accessibilityRole="button" accessibilityLabel={t('Icon: {name}', { name: md.replaceAll('_', ' ') })}
      accessibilityState={{ selected: symbol === sf }} onPress={() => setSymbol(sf)}
      style={[styles.iconButton, { backgroundColor: symbol === sf ? theme.selected : theme.surface }]}>
      <CategoryIcon symbol={sf} color={symbol === sf ? theme.link : theme.text} />
    </Pressable>
  ));
  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <SafeAreaView style={[styles.root, { backgroundColor: theme.background }]}>
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.root}>
          <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>
            <View style={styles.toolbar}>
              <ActionButton title={t('Cancel')} onPress={onClose} />
              <ActionButton title={t('Save')} onPress={save} isPrimary isDisabled={!canSave} />
            </View>
            <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t(isNew ? 'Add category' : 'Edit category')}</Text>
            <Text style={[styles.label, { color: theme.text }]}>{t('Name')}</Text>
            <TextInput autoFocus={isNew} accessibilityLabel={t('Name')} value={name} onChangeText={setName} maxLength={100}
              style={[styles.input, { color: theme.text, backgroundColor: theme.surface }]} />
            <Text style={[styles.label, { color: theme.text }]}>{t('Monthly limit (R$)')}</Text>
            <TextInput accessibilityLabel={t('Monthly limit (R$)')} value={limit} onChangeText={setLimit}
              keyboardType="decimal-pad" placeholder={t('No limit')} placeholderTextColor={theme.textSecondary}
              style={[styles.input, { color: theme.text, backgroundColor: theme.surface }]} />
            {parsed === 'invalid' && <Text accessibilityRole="alert" style={{ color: theme.warning }}>{t('Enter a positive amount, like 1.234,50.')}</Text>}
            <Text style={[styles.label, { color: theme.text }]}>{t('Icon')}</Text>
            <View style={styles.icons}>{icons}</View>
            {!isNew && <ActionButton title={t('Delete category')} onPress={confirmDelete} />}
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
  );
}

export function CategoriesScreen() {
  const theme = useTheme();
  const { settings } = expenseStore.useValue();
  const { data: account } = accountStore.useValue();
  const [editor, setEditor] = useState<{ category: ExpenseCategory; isNew: boolean } | null>(null);
  const [reordering, setReordering] = useState(false);
  const [suggestionNote, setSuggestionNote] = useState('');
  const now = new Date();
  const month = now.getFullYear() * 100 + now.getMonth() + 1;
  const monthLabel = now.toLocaleDateString(language === 'pt' ? 'pt-BR' : 'en-US', { month: 'long', year: 'numeric' });
  const rows = classifyExpenses(account.transactions, settings);
  const spent = spendingByCategory(rows, month);
  const totalSpent = [...spent.values()].reduce((sum, amount) => sum + amount, 0);
  const uncategorized = spent.get(undefined) ?? 0;
  const largePurchases = settings.largePurchase ? rows.filter((row) => row.kind === 'spending' && Math.floor(row.day / 100) === month && row.amount > settings.largePurchase!).length : 0;
  function suggest() {
    const result = suggestLimits(settings, rows, month);
    expenseStore.set({ settings: result.settings });
    setSuggestionNote(result.months ? t('Suggested {count} limits from the previous {months} months + 10%. Adjust as you like.', { count: result.count, months: result.months }) : t('Not enough history yet.'));
  }
  function move(id: string, offset: number) {
    const categories = [...expenseStore.get().settings.categories];
    const index = categories.findIndex((category) => category.id === id);
    const destination = index + offset;
    if (index < 0 || destination < 0 || destination >= categories.length) return;
    [categories[index], categories[destination]] = [categories[destination], categories[index]];
    updateSettings({ categories });
  }
  const categoryRows = settings.categories.map((category, index) => {
    const name = categoryName(category.name);
    return (
      <View key={category.id} style={styles.categoryRow}>
        <Pressable accessibilityRole="button" accessibilityLabel={t('Edit {name}', { name })}
          onPress={() => setEditor({ category, isNew: false })} style={styles.categoryMain}>
          <View style={[styles.categoryIcon, { backgroundColor: theme.selected }]}><CategoryIcon symbol={category.symbol} color={theme.text} /></View>
          <View style={styles.categoryDetail}>
            <Text style={[styles.label, { color: theme.text }]}>{name}</Text>
            <Spending spent={spent.get(category.id) ?? 0} limit={category.limit} alertAt={settings.alertAt} />
            {!category.limit && <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('No limit')}</Text>}
          </View>
          {!reordering && <Text style={{ color: theme.textSecondary }}>›</Text>}
        </Pressable>
        {reordering && <View style={styles.reorderControls}>
          <Pressable accessibilityRole="button" accessibilityLabel={t('Move {name} up', { name })} accessibilityState={{ disabled: index === 0 }}
            disabled={index === 0} onPress={() => move(category.id, -1)} style={styles.moveButton}>
            <Text style={{ color: index === 0 ? theme.textSecondary : theme.link }}>↑</Text>
          </Pressable>
          <Pressable accessibilityRole="button" accessibilityLabel={t('Move {name} down', { name })} accessibilityState={{ disabled: index === settings.categories.length - 1 }}
            disabled={index === settings.categories.length - 1} onPress={() => move(category.id, 1)} style={styles.moveButton}>
            <Text style={{ color: index === settings.categories.length - 1 ? theme.textSecondary : theme.link }}>↓</Text>
          </Pressable>
        </View>}
      </View>
    );
  });
  const warningPercent = Math.round(settings.alertAt * 100);
  return (
    <SafeAreaView edges={[]} style={[styles.root, { backgroundColor: theme.background }]}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.root}>
        <ScrollView contentContainerStyle={styles.content} keyboardDismissMode="on-drag" keyboardShouldPersistTaps="handled">
          <Text style={[styles.caption, { color: theme.textSecondary }]}>{t('Personal account · saved on this device.')}</Text>
          <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{monthLabel}</Text>
          <SettingsGroup title={t('Whole month')} footer={t('Limits are per month. Warnings appear here when spending reaches the chosen share or exceeds a limit.')}>
            <View style={styles.field}>
              <Text style={[styles.label, { color: theme.text }]}>{t('Spent this month')}</Text>
              <Spending spent={totalSpent} limit={settings.totalLimit} alertAt={settings.alertAt} />
            </View>
            <AmountField key={settings.totalLimit ?? 'none'} label={t('Monthly total limit (R$)')} value={settings.totalLimit} onCommit={(totalLimit) => updateSettings({ totalLimit })} />
            <View style={styles.field}>
              <Text style={[styles.label, { color: theme.text }]}>{t('Warn at')}</Text>
              <View style={styles.threshold}>
                <ActionButton accessibilityLabel={t('Decrease warning threshold')} title="−" isDisabled={warningPercent <= 50} onPress={() => updateSettings({ alertAt: Math.max(50, warningPercent - 5) / 100 })} />
                <Text accessibilityLiveRegion="polite" style={[styles.label, { color: theme.text }]}>{t('{percent}% of the limit', { percent: warningPercent })}</Text>
                <ActionButton accessibilityLabel={t('Increase warning threshold')} title="+" isDisabled={warningPercent >= 100} onPress={() => updateSettings({ alertAt: Math.min(100, warningPercent + 5) / 100 })} />
              </View>
            </View>
            <AmountField label={t('Warn about purchases over (R$)')} placeholder={t('Off')} value={settings.largePurchase} onCommit={(largePurchase) => updateSettings({ largePurchase })} />
            {largePurchases > 0 && <Text accessibilityRole="alert" style={[styles.field, { color: theme.warning }]}>{t('{count} purchases above your warning amount this month.', { count: largePurchases })}</Text>}
            <View style={styles.field}>
              <ActionButton title={t('Suggest limits from history')} onPress={suggest} />
              {!!suggestionNote && <Text accessibilityLiveRegion="polite" style={[styles.caption, { color: theme.textSecondary }]}>{suggestionNote}</Text>}
            </View>
          </SettingsGroup>
          <View style={styles.toolbar}>
            <Text accessibilityRole="header" style={[styles.heading, { color: theme.text }]}>{t('Categories')}</Text>
            <ActionButton title={t(reordering ? 'Done' : 'Reorder')} onPress={() => setReordering(!reordering)} />
          </View>
          <SettingsGroup title={t('Monthly spending')} footer={t('Tap a category to change its name, icon or limit. Deleting it sends its purchases back to “To review”.')}>
            {categoryRows}
            {uncategorized > 0 && <View style={styles.field}>
              <Text style={[styles.label, { color: theme.warning }]}>{t('No category')}</Text>
              <Text style={{ color: theme.warning }}>{moneyFormat.format(uncategorized)}</Text>
            </View>}
            <View style={styles.field}><ActionButton title={t('Add category')} onPress={() => setEditor({ category: newCategory(t('New category')), isNew: true })} /></View>
          </SettingsGroup>
        </ScrollView>
      </KeyboardAvoidingView>
      {editor && <CategoryEditor category={editor.category} isNew={editor.isNew} onClose={() => setEditor(null)} />}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 20, paddingBottom: 32 },
  heading: { fontSize: 22, fontWeight: '600' },
  label: { fontSize: 16, fontWeight: '500' },
  caption: { fontSize: 13, lineHeight: 19 },
  field: { padding: 16, gap: 10 },
  input: { minHeight: 48, borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, fontSize: 17 },
  toolbar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  threshold: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' },
  categoryRow: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, gap: 8 },
  categoryMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 16, minHeight: 72 },
  categoryIcon: { width: 44, height: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center' },
  categoryDetail: { flex: 1, gap: 6 },
  spending: { gap: 8 },
  track: { height: 4, borderRadius: 2, overflow: 'hidden' },
  fill: { height: 4 },
  icons: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  iconButton: { width: 48, height: 48, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  reorderControls: { flexDirection: 'row' },
  moveButton: { minWidth: 44, minHeight: 44, alignItems: 'center', justifyContent: 'center' },
});
