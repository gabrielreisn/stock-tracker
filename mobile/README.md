# Cymba for iOS and Android

The mobile client: an [Expo](https://docs.expo.dev) app (SDK 58, TypeScript, Expo Router). The four tabs share a personal account saved on the device. Pluggy connections supply accounts, holdings, transactions, closed card bills and loans. Stocks, bonds, funds, FGC Watcher, Expenses, Bills, Insights and Categories use that same data.

## Develop

From `mobile/`, with Node 24 and pnpm:

```sh
pnpm install
pnpm ios        # or: pnpm android
pnpm lint
pnpm typecheck
pnpm check:demo
pnpm check:insights
```

`ios/` and `android/` are generated and ignored by git: change native settings in `app.json`, not there. After adding a
native library or config plugin, run `pnpm expo prebuild` and then `pnpm ios` or `pnpm android` to rebuild.

## Layout

- `src/app/` — routes, one file per screen; `_layout.tsx` is the tab bar.
- `src/components/`, `src/hooks/`, `src/constants/theme.ts` — shared UI, hooks and color tokens.
- `src/lib/i18n.ts` — strings. As on macOS, the English text is the key, with a Portuguese translation for each.
- `src/types/` — shared TypeScript data contracts for the screen implementations.
- `src/data/demo/` — the macOS demo fixtures and `createDemoData()` loader. See [the data contract guide](src/data/README.md)
  for imports, date/currency conventions, and the checks (`pnpm check:demo`).

The tabs group the macOS sidebar, which has too many sections for a phone:

| Tab          | macOS sections                                              |
| ------------ | ----------------------------------------------------------- |
| Overview     | Overview                                                    |
| Investments  | Stocks, Bonds, Funds, FGC Watcher                             |
| Finances     | Expenses, Bills, Insights, Categories & limits, Open Finance |
| Settings     | Benchmarks and Open Finance, from Settings                  |

Open Finance works as on macOS: each user brings their own Pluggy application, and the app talks to `api.pluggy.ai`
directly, with Pluggy's own `react-native-pluggy-connect` for the Connect widget. The client secret stays in the iOS Keychain or Android Keystore (`expo-secure-store`); everything else in
Settings is plain preferences (`expo-sqlite/kv-store`).

Pluggy authorization uses the system browser. Every Connect token includes
`options.oauthRedirectUri`, built with `expo-linking` for the existing Settings route.
Native Cymba builds return to `cymba://settings`; the mounted widget then detects the Item's
status through Pluggy's polling. The callback itself is not proof of a successful connection.

For Expo Go, start with `pnpm exec expo start --go --lan` and open the LAN project URL.
Its return link uses `exp://<LAN address>:8081/--/settings`. Pluggy rejects localhost/127.0.0.1
callbacks, and Expo Go cannot register `cymba://`. Use a Cymba native build for a stable
callback scheme. Test create/reconnect token requests with `pnpm check:pluggy`.

## Open Finance and local data

Open **Finances → Open Finance** to see connected institutions, account balances and every
reported investment. Supported active positions are imported automatically. Stocks aggregate
quantities and acquisition costs; bonds use reported terms; funds use their CNPJ and statement
prices. Missing terms are not invented, and closed records remain available for review.
Stock holdings imported from snapshots start their performance history on the import date;
Pluggy's investment list is not a historical trade ledger.

`account-store.ts` persists the personal portfolio, expense settings, transaction cache, card
bills and loans in `expo-sqlite/kv-store`. `pluggy-store.ts` separately persists connection
snapshots and the last successful refresh. Credentials stay in secure storage. Data survives
reloads and works offline; a failed institution retains its previous snapshot. No demo positions,
transactions or budgets are seeded. Original macOS fixtures remain only for regression tests.

The first sync requests transactions from the beginning of the previous calendar year.
Subsequent syncs refresh the last three months. Opening older expense months or Insights years
fetches those months into the same cache. Categories, overrides, manual purchases and bill
choices are shared across screens and saved when edited.

A six-hour freshness check runs on launch, foreground resume and once a minute while active.
Native builds also register `cymba-open-finance-sync` with a **360-minute minimum interval**
through `expo-background-task`. The OS chooses the actual background execution time; this
is not an exact cron schedule. Failed attempts retry no more often than every 15 minutes;
manual Sync now bypasses that delay. Unsupported bill/loan products retain cached data and
show a warning without blocking portfolio refresh.

Background execution requires a rebuilt native app on a physical device; Expo Go and the iOS
simulator use the foreground fallback. The config plugin applies iOS background processing
settings during prebuild. On iOS the secret is stored with AFTER_FIRST_UNLOCK accessibility
so a scheduled task can authenticate while locked after the first unlock following reboot.
No API keys or secrets are stored in the account/cache records.

Run `pnpm check:open-finance` for persistence, mapping, partial failures, redemption and sync
race checks, and `pnpm check:pluggy` for the OAuth token contract. Pricing and classification
regression checks continue to use synthetic fixtures and do not access your accounts.

## Release

Builds go through EAS (`eas.json`). The first time, run `eas init` to link the project to an Expo account; then
`eas build --profile preview` for an internal build, or `eas build --profile production` and `eas submit` for the stores.

## First-launch setup

New installations show the same six-step setup guide as macOS: welcome, Meu Pluggy account,
Pluggy dashboard credentials, Open Finance connection, expense categories, and a final review.
Setup can be skipped; continuing past Open Finance requires at least one connection. Credentials
and connections use the same controls and storage as Settings. The final review opens Finances →
Open Finance. Nothing is imported automatically by the guide.

The SQLite `onboardingSeen` marker is written when the guide opens, independently of app versions.
Finishing, skipping, or quitting midway all leave it recorded, so relaunches and updates do not
reopen setup. Installations with saved account data, Pluggy settings/cache, or benchmark preferences
are treated as existing users and bypass setup. The marker uses app storage rather than Keychain;
a fresh installation with no restored app data can show the guide again.

Run `pnpm check:onboarding` for lifecycle and category-selection regression checks. To test the
welcome flow manually, use a fresh simulator installation without restored data; an existing
installation should go directly to the app. Force-quit during setup and reopen to verify it stays
closed, then install a newer build over that installation to verify the same behavior on updates.
