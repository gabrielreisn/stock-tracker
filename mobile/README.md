# Cymba for iOS and Android

The mobile client: an [Expo](https://docs.expo.dev) app (SDK 58, TypeScript, Expo Router). So far it's the shell, with
the five tabs and no data yet.

## Develop

From `mobile/`, with Node 24 and pnpm:

```sh
pnpm install
pnpm ios        # or: pnpm android
pnpm lint
pnpm typecheck
```

`ios/` and `android/` are generated and ignored by git: change native settings in `app.json`, not there. Once the app
uses a native library Expo Go doesn't include, run it with `pnpm expo run:ios` or `pnpm expo run:android`.

## Layout

- `src/app/` — routes, one file per screen; `_layout.tsx` is the tab bar.
- `src/components/`, `src/hooks/`, `src/constants/theme.ts` — shared UI, hooks and color tokens.
- `src/lib/i18n.ts` — strings. As on macOS, the English text is the key, with a Portuguese translation for each.

The tabs group the macOS sidebar, which has too many sections for a phone:

| Tab          | macOS sections                                              |
| ------------ | ----------------------------------------------------------- |
| Overview     | Overview                                                    |
| Investments  | Stocks, Bonds, Funds, FGC Watcher, Fund Comparison          |
| Finances     | Expenses, Bills, Insights, Categories & limits, Open Finance |
| AI           | AI                                                          |
| Settings     | Settings                                                    |

## Release

Builds go through EAS (`eas.json`). The first time, run `eas init` to link the project to an Expo account; then
`eas build --profile preview` for an internal build, or `eas build --profile production` and `eas submit` for the stores.
