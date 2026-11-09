# Mobile account data

Production screens consume one reactive `accountStore` from `@/lib/account-store`, backed by
`expo-sqlite/kv-store` under `personal-account-v1`. It starts with empty holdings, transactions,
bills and loans, plus the desktop default category names/keywords without demonstration limits.
The previous demo stores were session-only, so replacing them clears their synthetic data
without touching Pluggy client credentials or saved Item IDs.

`expenseStore` and `fundStore` are adapters to that account, not separate copies. `stock-store`,
`bond-store` and `bills-store` also share it. All writes persist before notifying React subscribers.
Use these APIs rather than creating independent screen state for financial records.

`pluggy-store` saves accounts, Items, investments and the successful refresh timestamp separately
under `pluggy-cache-v1`. Each connection is replaced only after a complete accounts/investments
response from an UPDATED Item. Failed/incomplete connections retain their prior snapshot.
Transaction, card-bill and loan requests also keep their previous data on failure. A generation
check discards in-flight responses after credentials or connections are removed.

`open-finance.ts` imports open positions: stocks/ETFs by ticker with weighted acquisition costs,
bonds by code and reported issue/maturity/rate terms, funds by CNPJ. Records beginning with
`pluggy-` are managed by reconciliation. Other manual positions survive unrelated syncs.
Explicitly closed positions and positions absent from a complete updated snapshot are removed;
reported positions with temporarily incomplete terms retain existing imported holdings. Unknown
or unsupported records remain visible in Open Finance. A gross balance alone is never treated
as a stock's acquisition cost. Snapshot imports do not invent historical trades.

`pluggy-refresh.ts` defines the native background task at module scope and registers it with a
360-minute minimum interval. Root navigation installs the foreground freshness checks. Native
packages are loaded only when present, so Expo Go and older binaries can continue running.
The OS determines the actual background schedule; the six-hour foreground check is the fallback.

## Contracts and formats

Import shared TypeScript contracts from `@/types`. They are compile-time contracts, not runtime
validators. They mirror the fields consumed by macOS Models, Bonds, FundHoldings, Expenses and
Pluggy. `AccountData` extends the original fixture-shaped contract with `cardBills` and `loans`.

| Representation | Meaning |
| --- | --- |
| `DayKey` | Calendar number YYYYMMDD, not epoch time |
| `MonthKey` | Calendar number YYYYMM; JSON object keys use strings |
| `ISODateString` | Trade, alert and Pluggy date strings |
| `AppleTimestamp` | Cache seconds since 2001-01-01 UTC; convert using `(value + 978307200) * 1000` |

Amounts use decimal currency units; bond rates are percentages, while expense `alertAt` is a
fraction. CNPJs and identifiers stay strings. Classify bank/card transactions using account and
transaction type before normalizing amount signs. Expense overrides preserve Swift's
associated-value JSON: `{category:{_0:id}}`, `{outside:{}}`, or `{deleted:{}}`. JSON sets are arrays.
Optional Pluggy fields may be omitted or null. Foreign purchases without a bank-provided BRL
conversion remain marked as unavailable rather than being added to BRL totals.

## Regression fixtures

`demo/` contains byte-for-byte copies of the six macOS demo JSON files and a date-shifting
`createDemoData()` factory, exclusively for regression tests and deliberate previews. No runtime
screen/store imports that factory. Refresh fixtures from `macOS/Resources/Demo/` and run
`pnpm check:demo`; update `DEMO_BASE_MONTH` if the source's final month changes.

`pnpm check:open-finance` exercises empty migration, imports, weighted prices, local persistence,
six-hour boundaries, failed-bank retention, incomplete terms, closed positions and connection
removal during sync. Existing feature checks use synthetic records only.
