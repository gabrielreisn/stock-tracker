# Data contracts for mobile screens

Import shared types from `@/types`. These are TypeScript compile-time contracts, not runtime
validators. They mirror the fields consumed by `macOS/Sources/StockBar/{Models,Bonds,
FundHoldings,Expenses,Pluggy}.swift`. Keep domain types here rather than declaring a second
version inside a screen. Existing `pluggy-client` and `benchmarks` type exports remain compatible.

```ts
import { createDemoData } from '@/data/demo';
import type { Bond, ExpenseSettings, FundHolding, PluggyTransaction, Trade } from '@/types';

const demo = createDemoData(); // fresh, editable in-memory account
const preview = createDemoData(20261109); // deterministic YYYYMMDD date for previews
```

The factory returns `trades`, `bonds`, `fundHoldings`, `alerts`, `expenses`, and `transactions`.
`transactions` contains `months`, `accounts`, `fetchedAt`, and `currencyRead`. It performs no
network or storage operations. Screens can consume it independently; wiring a demo/personal
account selector and persistent stores is future work. Never merge this account into the
personal Pluggy store or sync its synthetic item IDs.

## Fixtures and dates

The six JSON files in `demo/` are byte-for-byte copies of `macOS/Resources/Demo/`, generated
there by `macOS/scripts/demo-data.py`. They contain 18 trades, six bonds, five fund holdings,
two alerts, 15 expense categories, two accounts, and 24 months of transactions ending October
2026. To refresh, copy those six files again and run `pnpm check:demo`. Update
`DEMO_BASE_MONTH` if the source's final transaction month changes.

The loader follows `DataAccount.prepareDemo`: move transaction months and card purchase dates
by the same offset so the last month is the requested month, clamp days to the destination
month's end, and exclude transactions after today. It preserves IDs, time suffixes, and original
trade/bond/fund dates. Categories keep their English source names for the UI to translate.

| Representation | Meaning |
| --- | --- |
| `DayKey` | Number `YYYYMMDD`; calendar date, not epoch time |
| `MonthKey` | Number `YYYYMM`; JSON dictionary keys are strings |
| `ISODateString` | Trade and Pluggy dates, e.g. `2024-02-14T15:00:00Z` |
| `AppleTimestamp` | Seconds since 2001-01-01 UTC; convert with `new Date((value + 978307200) * 1000)` |

`fetchedAt` uses the desktop's future demo marker (4,000,000,000 Apple seconds), not the current
fetch time. An alert's optional `triggeredAt` uses ISO 8601, like trades (`PortfolioStore.saveAlerts`). JSON sets are arrays.
`ExpenseOverride` preserves Swift's associated-value JSON (`{ category: { _0: id } }`,
`{ outside: {} }`, or `{ deleted: {} }`). Missing optional domain fields are omitted; nullable
Pluggy API fields may also be explicit `null`. `Expense` is a derived UI row; its `foreign.conversion`
uses a TypeScript discriminated union rather than a persisted Swift encoding.

## Amounts and incomplete data

Amounts are decimal currency units. Trades and alerts use the ticker's currency; bonds are BRL.
CNPJs, account numbers and IDs stay strings. Bond rates are percentages (13.2 means 13.2%);
expense `alertAt` is a fraction (0.8 means 80%).

Bank transaction debits leave the account and credits enter it. Card debits are purchases;
credits are refunds or bill payments. The source contains negative bank debits and positive
card debits: classify using account type and transaction type before normalizing amounts.
Do not treat every negative amount as spending. Categories/rules/overrides still need a
classification layer; the factory doesn't derive `Expense` rows.

Demo holdings are inputs, not valuations: fetch public price histories, CDI/IPCA and CVM prices
or supply explicit UI placeholders. The fixtures do not contain derived returns, stock holdings,
closed card bills, loans, dividend calendars or market caches. `PluggyBill` and `PluggyLoan`
types describe future live data, not invented demo records.

`pnpm check:demo` checks source parity, literal fixture compatibility with the contracts, account
references, date shifting (including February/leap years), future filtering, and copy isolation.

## Bills screen

Finances → Bills consumes a separate in-memory demo account. Its classification and recurring
bill derivation live in `src/lib/bills.ts`; choices live in `demo-bills-store.ts` for the app
session only. It follows the desktop's 2-of-3-month detection, median payment day, three-day
grace period, monthly paid markers and month-end clamping. Pull to refresh advances the demo
if the calendar day changed. Closed card bills and loans show empty states because the
fixtures do not include those records. Run `pnpm check:bills` for the behavior checks.
