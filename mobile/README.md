# Cymba for iOS and Android

The mobile client: an [Expo](https://docs.expo.dev) app (SDK 58, TypeScript, Expo Router). It has four tabs, the
Bills and Insights screens under Finances, and benchmarks and Open Finance connections in Settings.

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
| Investments  | Stocks, Bonds, Funds, FGC Watcher, Fund Comparison          |
| Finances     | Expenses, Bills, Insights, Categories & limits, Open Finance |
| Settings     | Benchmarks and Open Finance, from Settings                  |

Open Finance works as on macOS: each user brings their own Pluggy application, and the app talks to `api.pluggy.ai`
directly, with Pluggy's own `react-native-pluggy-connect` for the Connect widget. The client secret stays in the iOS Keychain or Android Keystore (`expo-secure-store`); everything else in
Settings is plain preferences (`expo-sqlite/kv-store`).

## Insights

Open **Finances → Insights** to explore the isolated demo account. The screen mirrors the macOS yearly summaries,
monthly spending chart (category focus, trend and limits), category trends and twelve-month table. Tap a chart month
for its value, tap a category to focus the chart, and swipe the chart or table horizontally for the full year. The year
selector covers the current and previous two years. English/Portuguese strings and light/dark themes follow the device.

`src/lib/insights.ts` classifies the demo transactions and derives yearly analytics without network or storage access.
Averages and least-squares trends use completed months; installments are assigned to their billing months.
`pnpm check:insights` verifies fixture totals, exclusions, overrides, currency handling, installments and trend boundaries.
Personal-account selection and persistence remain future work, as described in the data guide.

## Release

Builds go through EAS (`eas.json`). The first time, run `eas init` to link the project to an Expo account; then
`eas build --profile preview` for an internal build, or `eas build --profile production` and `eas submit` for the stores.
