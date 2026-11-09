import { t } from '@/lib/i18n';

import type { PluggyAccount, PluggyInvestment, PluggyItem } from '@/types';
export type { PluggyAccount, PluggyInvestment, PluggyItem } from '@/types';

type Page<T> = { results: T[]; totalPages?: number };

const BASE_URL = 'https://api.pluggy.ai';
const REQUEST_TIMEOUT_MS = 30_000;
/** API keys last two hours; renewing a little early avoids one expiring mid-sync. */
const API_KEY_LIFETIME_MS = 110 * 60 * 1000;

async function send<T>(path: string, init: RequestInit = {}): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(`${BASE_URL}/${path}`, { ...init, signal: controller.signal });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(t('Pluggy returned {code}: {message}', {
        code: response.status,
        message: failureMessage(text),
      }));
    }
    return JSON.parse(text) as T;
  } finally {
    clearTimeout(timeout);
  }
}

function failureMessage(body: string): string {
  try {
    const parsed = JSON.parse(body) as { message?: unknown };
    if (typeof parsed.message === 'string') return parsed.message;
  } catch {
    // Not JSON: show the start of whatever came back.
  }
  return body.slice(0, 200);
}

/** Pluggy's REST API (api.pluggy.ai): client credentials buy a 2-hour API key, sent as X-API-KEY. */
export function createPluggyClient(clientId: string, clientSecret: string) {
  let apiKey: { key: string; expires: number } | null = null;

  async function key(): Promise<string> {
    if (apiKey && apiKey.expires > Date.now()) return apiKey.key;
    const auth = await send<{ apiKey: string }>('auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    });
    apiKey = { key: auth.apiKey, expires: Date.now() + API_KEY_LIFETIME_MS };
    return auth.apiKey;
  }

  async function get<T>(path: string, query: Record<string, string> = {}): Promise<T> {
    const search = new URLSearchParams(query).toString();
    return send<T>(search ? `${path}?${search}` : path, { headers: { 'X-API-KEY': await key() } });
  }

  async function all<T>(path: string, itemId: string): Promise<T[]> {
    const results: T[] = [];
    for (let page = 1; ; page += 1) {
      const current = await get<Page<T>>(path, { itemId, page: String(page), pageSize: '500' });
      results.push(...current.results);
      if (!current.totalPages || page >= current.totalPages) return results;
    }
  }

  return {
    authenticate: key,
    item: (id: string) => get<PluggyItem>(`items/${id}`),
    accounts: (itemId: string) => all<PluggyAccount>('accounts', itemId),
    investments: (itemId: string) => all<PluggyInvestment>('investments', itemId),

    /** A 30-minute token for the Connect widget; with `itemId`, it reconnects that item instead of adding one. */
    async connectToken(itemId: string | null, oauthRedirectUri: string): Promise<string> {
      if (['localhost', '127.0.0.1', '[::1]'].includes(new URL(oauthRedirectUri).hostname)) {
        throw new Error(t('To connect in Expo Go, restart Metro with --lan and reopen the project.'));
      }
      // No avoidDuplicates: MeuPluggy items carry no credentials, so Pluggy would treat every new one as a
      // duplicate, yet each one shares a different institution. Cymba dedupes by accounts after syncing.
      const token = await send<{ accessToken: string }>('connect_token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-API-KEY': await key() },
        body: JSON.stringify({
          ...(itemId ? { itemId } : {}),
          options: { oauthRedirectUri },
        }),
      });
      return token.accessToken;
    },

    /** The MeuPluggy connector's id: personal applications connect through it. */
    async meuPluggyConnectorId(): Promise<number | null> {
      try {
        const page = await get<Page<{ id: number; name: string }>>('connectors', { name: 'MeuPluggy' });
        const match = page.results.find(
          (connector) => connector.name.toLowerCase().replace(/[^a-z]/g, '') === 'meupluggy',
        );
        return match?.id ?? null;
      } catch {
        return null;
      }
    },
  };
}
