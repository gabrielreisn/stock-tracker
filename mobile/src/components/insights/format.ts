import { language, t, type StringKey } from '@/lib/i18n';

export const locale = language === 'pt' ? 'pt-BR' : 'en-US';
const currency = new Intl.NumberFormat(locale, { style: 'currency', currency: 'BRL', maximumFractionDigits: 2 });
const whole = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 });
export const money = (value: number) => currency.format(value);
export const wholeAmount = (value: number) => value === 0 ? '–' : whole.format(value);
export function monthName(month: number, long = false) {
  return new Date(Math.floor(month / 100), month % 100 - 1, 1).toLocaleDateString(locale, { month: long ? 'long' : 'short' });
}
export function categoryName(name?: string) {
  if (!name) return t('No category');
  // Fixture names are English keys; user-created names remain verbatim.
  const names: StringKey[] = ['Groceries & Cleaning', 'Home & Furniture', 'Delivery & Restaurants', 'Transport & Travel',
    'Health & Pharmacy', 'Beauty & Self-care', 'Electronics & Tech', 'Subscriptions & Apps', 'Books & Education',
    'Pets', 'Clothing & Accessories', 'Leisure & Games', 'Housing & Bills', 'PIX & Transfers', 'Shopping'];
  return names.includes(name as StringKey) ? t(name as StringKey) : name;
}
