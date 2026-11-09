import * as SecureStore from 'expo-secure-store';
import Storage from 'expo-sqlite/kv-store';

import { accountStore } from '@/lib/account-store';
import { todayKey, monthOffset } from '@/lib/bills';
import { reconcilePortfolio, syncIsDue } from '@/lib/open-finance';
import type { PluggyBill, PluggyLoan, PluggyTransaction } from '@/types';

import { createStore } from '@/lib/external-store';
import { t } from '@/lib/i18n';
import {
  createPluggyClient,
  type PluggyAccount,
  type PluggyInvestment,
  type PluggyItem,
} from '@/lib/pluggy-client';

const CLIENT_ID_KEY = 'pluggyClientId';
const ITEMS_KEY = 'pluggyItems';
/** Lives in the iOS Keychain or Android Keystore, never in preferences. */
const SECRET_KEY = 'pluggyClientSecret';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function loadItemIDs(): string[] {
  try {
    const saved: unknown = JSON.parse(Storage.getItemSync(ITEMS_KEY) ?? '[]');
    return Array.isArray(saved) ? saved.filter((id) => typeof id === 'string' && UUID.test(id)) : [];
  } catch {
    return [];
  }
}

function loadSecret(): string | null {
  try {
    return SecureStore.getItem(SECRET_KEY);
  } catch {
    // Android can lose the key that encrypts this, e.g. after restoring a backup: ask for the secret again.
    return null;
  }
}

const CACHE_KEY = 'pluggy-cache-v1';
interface Snapshot {
  items: PluggyItem[];
  accounts: PluggyAccount[];
  investments: PluggyInvestment[];
  lastSync: Date | null;
}
function loadCache(): Snapshot {
  try {
    const saved = JSON.parse(Storage.getItemSync(CACHE_KEY) ?? 'null');
    if (saved && Array.isArray(saved.accounts) && Array.isArray(saved.investments)) {
      return { ...saved, lastSync: saved.lastSync ? new Date(saved.lastSync) : null };
    }
  } catch { /* Keep credentials and connections even if their data cache is unreadable. */ }
  return { items: [], accounts: [], investments: [], lastSync: null };
}
let generation = 0;
let inFlight: Promise<boolean> | null = null;
let lastAttempt = 0;
let secret = loadSecret();

const store = createStore({
  clientId: Storage.getItemSync(CLIENT_ID_KEY) ?? '',
  itemIDs: loadItemIDs(),
  hasSecret: secret !== null,
  ...loadCache(),
  isSyncing: false,
  error: null as string | null,
});

export type PluggyState = ReturnType<typeof store.get>;
export type ConnectSession = { token: string; connectorId: number | null };

export const usePluggy = store.useValue;

export function isConfigured(state: PluggyState): boolean {
  return state.clientId !== '' && state.hasSecret;
}

/** Items that need the user again: consent expired after a year, or a login error. */
export function needsReconnect(state: PluggyState, id: string): boolean {
  const item = state.items.find((candidate) => candidate.id === id);
  if (!item) return false;
  return item.error != null || ['LOGIN_ERROR', 'OUTDATED', 'WAITING_USER_INPUT'].includes(item.status ?? '');
}

/** The institutions behind a connection, from its accounts (a MeuPluggy item is named after the connector only). */
export function institutionsOf(state: PluggyState, id: string): string | null {
  const accounts = state.accounts.filter((account) => account.itemId === id);
  const bank = accounts.filter((account) => account.type === 'BANK');
  const names = (bank.length > 0 ? bank : accounts).flatMap((account) => account.marketingName ?? account.name ?? []);
  return names.length > 0 ? [...new Set(names)].join(', ') : null;
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function client() {
  const { clientId, hasSecret } = store.get();
  if (!clientId || !hasSecret || secret === null) return null;
  return createPluggyClient(clientId, secret);
}

export function setClientId(value: string) {
  const clientId = value.trim();
  store.set({ clientId });
  Storage.setItemSync(CLIENT_ID_KEY, clientId);
}

export async function saveSecret(value: string): Promise<boolean> {
  const trimmed = value.trim();
  if (!store.get().clientId || !trimmed) return false;
  try {
    await SecureStore.setItemAsync(SECRET_KEY, trimmed, { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK });
  } catch {
    store.set({ error: t("Couldn't save the secret on this device.") });
    return false;
  }
  secret = trimmed;
  store.set({ hasSecret: true, error: null });
  return true;
}

export async function prepareBackgroundCredentials() {
  if (secret) await SecureStore.setItemAsync(SECRET_KEY, secret, { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK });
}

export async function forgetCredentials() {
  await SecureStore.deleteItemAsync(SECRET_KEY);
  secret = null;
  generation += 1;
  Storage.removeItemSync(CACHE_KEY);
  store.set({ hasSecret: false, items: [], accounts: [], investments: [], lastSync: null, error: null });
}

function saveItemIDs(itemIDs: string[]) {
  store.set({ itemIDs });
  Storage.setItemSync(ITEMS_KEY, JSON.stringify(itemIDs));
}

/** Stops syncing a connection. It stays in Pluggy. */
export function removeItem(id: string) {
  generation += 1;
  const state = store.get();
  saveItemIDs(state.itemIDs.filter((other) => other !== id));
  store.set({
    items: state.items.filter((item) => item.id !== id),
    accounts: state.accounts.filter((account) => account.itemId !== id),
    investments: state.investments.filter((investment) => investment.itemId !== id),
  });
  const { items, accounts, investments, lastSync } = store.get();
  Storage.setItemSync(CACHE_KEY, JSON.stringify({ items, accounts, investments, lastSync }));
}

/** What the Connect widget needs: a fresh token, and the MeuPluggy connector to offer when it can be found. */
export async function connectSession(updating: string | null, redirectUri: string): Promise<ConnectSession> {
  const pluggy = client();
  if (!pluggy) throw new Error(t('Add your Pluggy client ID and secret in Settings.'));
  const [token, connectorId] = await Promise.all([
    pluggy.connectToken(updating, redirectUri),
    pluggy.meuPluggyConnectorId(),
  ]);
  return { token, connectorId };
}

/** Shared by manual refresh, foreground freshness checks and the native background task. */
export function sync(): Promise<boolean> {
  if (inFlight) return inFlight;
  inFlight = performSync().finally(() => { inFlight = null; });
  return inFlight;
}

function iso(day: number) {
  const value = String(day);
  return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`;
}

async function performSync(): Promise<boolean> {
  lastAttempt = Date.now();
  const pluggy = client();
  if (!pluggy) { store.set({ error: t('Add your Pluggy client ID and secret in Settings.') }); return false; }
  const revision = generation;
  const before = store.get();
  if (!before.itemIDs.length) return true;
  store.set({ isSyncing: true, error: null });
  const failures: string[] = [];
  let coreSucceeded = true;
  let transactionsComplete = true;
  const items = [...before.items];
  const accounts = [...before.accounts];
  const investments = [...before.investments];
  let data = accountStore.get().data;
  let cardBills: PluggyBill[] = [...data.cardBills];
  let loans: PluggyLoan[] = [...data.loans];
  const months = structuredMonths(data.transactions.months);
  const today = todayKey();
  const currentMonth = Math.floor(today / 100);
  // First fetch seeds two calendar years for Insights. Subsequent syncs refresh recent statements.
  const startMonth = Object.keys(months).length ? monthOffset(currentMonth, -2) : (Math.floor(today / 10000) - 1) * 100 + 1;
  try {
    await pluggy.authenticate();
    for (const id of before.itemIDs) {
      try {
        const item = await pluggy.item(id);
        replaceByID(items, [item], row => row.id === id);
        // Incomplete institution snapshots must not erase positions as if they had been sold.
        if (item.status !== 'UPDATED') { coreSucceeded = false; continue; }
        const newAccounts = (await pluggy.accounts(id)).map(row => ({ ...row, itemId: id }));
        const newInvestments = (await pluggy.investments(id)).map(row => ({ ...row, itemId: id }));
        replaceByID(accounts, newAccounts, row => row.itemId === id);
        replaceByID(investments, newInvestments, row => row.itemId === id);
      } catch (error) { coreSucceeded = false; failures.push(`${id.slice(0, 8)}…: ${describe(error)}`); }
      try {
        const freshLoans = (await pluggy.loans(id)).map(row => ({ ...row, itemId: id }));
        loans = [...loans.filter(row => row.itemId !== id), ...freshLoans];
      } catch (error) { failures.push(`Loans ${id.slice(0, 8)}…: ${describe(error)}`); }
    }
    for (const account of accounts) {
      if (account.type !== 'BANK' && account.type !== 'CREDIT') continue;
      try {
        const transactions = await pluggy.transactions(account.id, iso(startMonth * 100 + 1), iso(today));
        for (const [key, rows] of Object.entries(months)) {
          if (Number(key) >= startMonth) months[key] = rows.filter(row => row.accountId !== account.id);
        }
        for (const row of transactions) {
          const key = row.date?.slice(0, 7).replace('-', '');
          if (key) (months[key] ??= []).push(row);
        }
      } catch (error) { transactionsComplete = false; coreSucceeded = false; failures.push(`Transactions ${account.name ?? account.id}: ${describe(error)}`); }
      if (account.type === 'CREDIT') {
        try {
          const bills = (await pluggy.bills(account.id)).map(row => ({ ...row, accountId: account.id }));
          cardBills = [...cardBills.filter(row => row.accountId !== account.id), ...bills];
        } catch (error) { failures.push(`Bills ${account.name ?? account.id}: ${describe(error)}`); }
      }
    }
    if (revision !== generation) return false;
    const active = new Set(store.get().itemIDs);
    const freshAccounts = accounts.filter(row => active.has(row.itemId ?? ''));
    const accountIDs = new Set(freshAccounts.map(row => row.id));
    for (const key of Object.keys(months)) months[key] = unique(months[key].filter(row => accountIDs.has(row.accountId ?? '')));
    const freshInvestments = investments.filter(row => active.has(row.itemId ?? ''));
    // Read user edits again after the network waits, so categorization made during a sync survives.
    data = reconcilePortfolio(accountStore.get().data, freshInvestments, today);
    const appleNow = Date.now() / 1000 - 978307200;
    const fetchedAt = { ...data.transactions.fetchedAt };
    if (transactionsComplete) {
      for (let month = startMonth; month <= currentMonth; month = monthOffset(month, 1)) fetchedAt[String(month)] = appleNow;
    }
    data = { ...data, cardBills: unique(cardBills.filter(row => accountIDs.has(row.accountId ?? ''))),
      loans: unique(loans.filter(row => active.has(row.itemId ?? ''))),
      transactions: { ...data.transactions, accounts: freshAccounts, months,
        fetchedAt } };
    accountStore.set({ data });
    const snapshot = { items: items.filter(row => active.has(row.id)), accounts: freshAccounts,
      investments: freshInvestments, lastSync: coreSucceeded ? new Date() : before.lastSync };
    Storage.setItemSync(CACHE_KEY, JSON.stringify(snapshot));
    store.set({ ...snapshot, error: failures.length ? failures.join('\n') : null });
    return coreSucceeded;
  } catch (error) {
    store.set({ error: describe(error) });
    return false;
  } finally { store.set({ isSyncing: false }); }
}
function unique<T extends { id: string }>(rows: T[]): T[] {
  return [...new Map(rows.map(row => [row.id, row])).values()];
}
function replaceByID<T>(rows: T[], fresh: T[], matches: (row: T) => boolean) {
  const retained = rows.filter(row => !matches(row));
  rows.splice(0, rows.length, ...retained, ...fresh);
}
function structuredMonths(months: Record<string, PluggyTransaction[]>) {
  return Object.fromEntries(Object.entries(months).map(([key, rows]) => [key, [...rows]]));
}

const loadingMonths = new Set<number>();
/** Fetch older months as the user opens them, using the same local cache as all finance screens. */
export async function loadTransactionMonth(month: number): Promise<void> {
  if (loadingMonths.has(month)) return;
  loadingMonths.add(month);
  try {
    if (inFlight) await inFlight;
    const cached = accountStore.get().data.transactions.fetchedAt[String(month)];
    if (cached && Date.now() - (cached + 978307200) * 1000 < 6 * 60 * 60_000) return;
    const pluggy = client();
    if (!pluggy) return;
    const revision = generation;
    const from = iso(month * 100 + 1);
    const next = monthOffset(month, 1);
    const last = new Date(Date.UTC(Math.floor(next / 100), next % 100 - 1, 0)).getUTCDate();
    const to = iso(month * 100 + last);
    let rows = [...(accountStore.get().data.transactions.months[String(month)] ?? [])];
    let complete = true;
    for (const account of store.get().accounts) {
      if (account.type !== 'BANK' && account.type !== 'CREDIT') continue;
      try {
        const fresh = await pluggy.transactions(account.id, from, to);
        rows = [...rows.filter(row => row.accountId !== account.id), ...fresh];
      } catch (error) { complete = false; store.set({ error: describe(error) }); }
    }
    if (revision !== generation || !store.get().accounts.length) return;
    const data = accountStore.get().data;
    const transactions = data.transactions;
    accountStore.set({ data: { ...data, transactions: { ...transactions,
      months: { ...transactions.months, [String(month)]: unique(rows) },
      fetchedAt: { ...transactions.fetchedAt, ...(complete ? { [String(month)]: Date.now() / 1000 - 978307200 } : {}) },
    } } });
  } finally { loadingMonths.delete(month); }
}

export function syncIfNeeded(): Promise<boolean> {
  const state = store.get();
  if (isConfigured(state) && state.itemIDs.length && syncIsDue(state.lastSync) && Date.now() - lastAttempt > 15 * 60_000) return sync();
  return Promise.resolve(true);
}

function accountSignature(state: PluggyState, id: string): Set<string> {
  return new Set(
    state.accounts
      .filter((account) => account.itemId === id)
      .map((account) => `${account.type ?? ''}|${account.number ?? ''}|${account.marketingName ?? account.name ?? ''}`),
  );
}

/**
 * After the widget succeeds: keep the item (a reconnect can hand back a new id) and sync it. An older connection
 * that turns out to share the same accounts (the same institution connected twice) is dropped from Cymba, so
 * nothing is counted twice; it stays in Pluggy.
 */
export async function connected(itemId: string, replacing: string | null) {
  // An automatic refresh begun before this new Item existed cannot fulfill its first sync.
  if (inFlight) await inFlight;
  const id = itemId.toLowerCase();
  if (replacing && replacing !== id) removeItem(replacing);
  const { itemIDs } = store.get();
  if (UUID.test(id) && !itemIDs.includes(id)) saveItemIDs([...itemIDs, id]);
  await sync();

  const state = store.get();
  const fresh = accountSignature(state, id);
  if (fresh.size === 0) return;
  const duplicates = state.itemIDs.filter((other) => {
    if (other === id) return false;
    const theirs = accountSignature(state, other);
    return theirs.size > 0 && [...theirs].every((signature) => fresh.has(signature));
  });
  duplicates.forEach(removeItem);
  if (duplicates.length > 0) await sync();
}
