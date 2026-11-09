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


## Spending notifications and category order

Categories & limits requests notification authorization through **Enable notifications**. At
first authorization it checks the current month's snapshot; subsequent account edits and
foreground/background Open Finance refreshes check again. Alerts use the selected percentage
(default 80%), an additional over-limit warning, the optional monthly total, and individual
purchases strictly above the configured amount. Later installments do not trigger purchase
alerts. Successfully delivered keys are persisted in `ExpenseSettings.notified`; denied
permission and failed scheduling leave keys eligible for retry. Notification taps open the
limits screen.

The `expo-notifications` config plugin configures the native build for local notifications.
iOS has no notification usage-description Info.plist key; authorization is requested at runtime.
The existing background-task plugin supplies the background processing Info.plist configuration.
APNs and remote-notification background mode are not needed for these local alerts. Existing
installed binaries need a new native build to include the notification module. OS scheduling
controls when background sync can discover new purchases; this is not a live bank push feed.

Drag a category's handle to reorder; the list scrolls at its edges. VoiceOver/TalkBack users
can use the handle's move-up/move-down actions. Run `pnpm check:notifications` for alert delivery,
permission/retry behavior and category ordering checks.

## Fund market data

The funds screen loads public CVM share-price reports on entry and on pull-to-refresh. FIFs
use `FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_YYYYMM.zip`; FIDCs use the
`inf_mensal_fidc_tab_X_2_YYYYMM.csv` table from the monthly FIDC ZIP. Like desktop, FIF
subclasses are not mixed with the class series; FIDC series use the greatest outstanding
share count. FIPs retain statement valuations without inventing public return histories.

The loader covers 16 months to accommodate reporting delays plus a 12-month baseline.
It streams decompression one archive at a time and stores only held funds' numeric rows in
SQLite, with a 12-hour cache. Pull-to-refresh bypasses that cache and refreshes connected
Open Finance holdings first. Failed downloads preserve cached quotes and show a retry message.

Trailing month, YTD and trailing year returns end on CVM's latest reporting day and use the
last quote on or before each calendar boundary, including leap-day clamping. A newer bank
statement changes valuation, not CVM returns. Missing baselines stay unavailable; summary
returns weight only positions with that period's return by their latest gross values.
Run `pnpm check:fund-market` for parser, valuation, return, caching and refresh regression checks.
