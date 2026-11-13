import Storage from 'expo-sqlite/kv-store';
import defaults from '@/data/default-categories.json';
import type { ExpenseCategory, ExpenseSettings } from '@/types';

// An installation marker, deliberately independent of app/build versions and credentials.
export const ONBOARDING_SEEN_KEY = 'onboardingSeen';
const existingInstallationKeys = [
  'personal-account-v1', 'pluggyClientId', 'pluggyItems', 'pluggy-cache-v1', 'benchmarks',
];

export function shouldShowOnboarding(): boolean {
  return Storage.getItemSync(ONBOARDING_SEEN_KEY) === null
    && !existingInstallationKeys.some(key => Storage.getItemSync(key) !== null);
}

export function markOnboardingSeen() {
  Storage.setItemSync(ONBOARDING_SEEN_KEY, 'true');
}

function starting(symbol: string): ExpenseCategory {
  return defaults.find(category => category.symbol === symbol)!;
}

// Same choices and precedence as ExpenseStore.onboardingCategories on macOS.
export const onboardingCategories: ExpenseCategory[] = [
  { id: 'onboarding-fixed', name: 'Fixed expenses', symbol: 'pin', pluggyKeywords: ['insurance', 'loan', 'financing'] },
  starting('bolt'), starting('arrow.triangle.2.circlepath'), starting('pawprint'),
  { id: 'onboarding-car', name: 'Car', symbol: 'car.side', pluggyKeywords: ['gas station', 'parking', 'toll', 'vehicle', 'automotive'] },
  starting('cart'), starting('fork.knife'), starting('cross.case'), starting('car'),
  starting('gamecontroller'), starting('bag'), starting('book'),
];

export function hasStartingCategories(settings: ExpenseSettings): boolean {
  return JSON.stringify(settings.categories) === JSON.stringify(defaults);
}

/** Preserve user categories and limits; remove references only when replacing the untouched defaults. */
export function adoptOnboardingCategories(settings: ExpenseSettings, picked: Set<string>): ExpenseSettings {
  const picks = onboardingCategories.filter(category => picked.has(category.id));
  if (picks.length === 0) return settings;
  if (!hasStartingCategories(settings)) {
    const existing = new Set(settings.categories.map(category => category.id));
    return { ...settings, categories: [...settings.categories, ...picks.filter(category => !existing.has(category.id))] };
  }
  const ids = new Set(picks.map(category => category.id));
  return {
    ...settings, categories: picks,
    rules: Object.fromEntries(Object.entries(settings.rules).filter(([, id]) => ids.has(id))),
    overrides: Object.fromEntries(Object.entries(settings.overrides).filter(([, value]) => !value.category || ids.has(value.category._0))),
    manual: settings.manual.map(row => row.categoryID && !ids.has(row.categoryID) ? { ...row, categoryID: undefined } : row),
  };
}
