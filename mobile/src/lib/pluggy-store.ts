import * as SecureStore from 'expo-secure-store';
import Storage from 'expo-sqlite/kv-store';

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

let secret = loadSecret();

const store = createStore({
  clientId: Storage.getItemSync(CLIENT_ID_KEY) ?? '',
  itemIDs: loadItemIDs(),
  hasSecret: secret !== null,
  items: [] as PluggyItem[],
  accounts: [] as PluggyAccount[],
  investments: [] as PluggyInvestment[],
  isSyncing: false,
  lastSync: null as Date | null,
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
    await SecureStore.setItemAsync(SECRET_KEY, trimmed);
  } catch {
    store.set({ error: t("Couldn't save the secret on this device.") });
    return false;
  }
  secret = trimmed;
  store.set({ hasSecret: true, error: null });
  return true;
}

export async function forgetCredentials() {
  await SecureStore.deleteItemAsync(SECRET_KEY);
  secret = null;
  store.set({ hasSecret: false, items: [], accounts: [], investments: [], lastSync: null, error: null });
}

function saveItemIDs(itemIDs: string[]) {
  store.set({ itemIDs });
  Storage.setItemSync(ITEMS_KEY, JSON.stringify(itemIDs));
}

/** Stops syncing a connection. It stays in Pluggy. */
export function removeItem(id: string) {
  const state = store.get();
  saveItemIDs(state.itemIDs.filter((other) => other !== id));
  store.set({
    items: state.items.filter((item) => item.id !== id),
    accounts: state.accounts.filter((account) => account.itemId !== id),
    investments: state.investments.filter((investment) => investment.itemId !== id),
  });
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

/** Fetches each connection with its accounts and investments. One that fails doesn't stop the others. */
export async function sync() {
  if (store.get().isSyncing) return;
  const pluggy = client();
  if (!pluggy) {
    store.set({ error: t('Add your Pluggy client ID and secret in Settings.') });
    return;
  }
  store.set({ isSyncing: true, error: null });
  try {
    await pluggy.authenticate();
    const items: PluggyItem[] = [];
    const accounts: PluggyAccount[] = [];
    const investments: PluggyInvestment[] = [];
    const failures: string[] = [];
    for (const id of store.get().itemIDs) {
      try {
        items.push(await pluggy.item(id));
        accounts.push(...(await pluggy.accounts(id)).map((account) => ({ ...account, itemId: account.itemId ?? id })));
        investments.push(
          ...(await pluggy.investments(id)).map((investment) => ({ ...investment, itemId: investment.itemId ?? id })),
        );
      } catch (error) {
        failures.push(`${id.slice(0, 8)}…: ${describe(error)}`);
      }
    }
    store.set({
      items,
      accounts,
      investments,
      lastSync: new Date(),
      error: failures.length > 0 ? failures.join('\n') : null,
    });
  } catch (error) {
    store.set({ error: describe(error) });
  } finally {
    store.set({ isSyncing: false });
  }
}

/** The first sync after launch, once the credentials and at least one connection are there. */
export function syncIfNeeded() {
  const state = store.get();
  if (isConfigured(state) && state.itemIDs.length > 0 && state.lastSync === null) void sync();
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
