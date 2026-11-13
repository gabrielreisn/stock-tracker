# Cymba Native for iPhone

Native SwiftUI and Swift Charts app matching the Cymba Expo client in `/mobile`, for **iOS 18+**, independent of Expo. Open `StockBar.xcodeproj` and run the **StockBar** scheme on an iPhone simulator. Xcode 26+ is required to compile the optional Foundation Models integration; Apple Intelligence needs iOS 26 and an eligible device.

For a physical phone, the project currently selects the local development team `7523M25J2L` for **StockBar** and **StockBarWidget**; choose your own team when building on another account. Both targets use the `group.app.cymba.native.shared` App Group for the portfolio widget; register that group with your team, or change it consistently in both entitlements and both snapshot implementations. Bundle IDs are `app.cymba.native` and `app.cymba.native.widget`.

```sh
xcodebuild -project ios/StockBar.xcodeproj -scheme StockBar \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Substitute an installed simulator's name or UUID.
xcodebuild -project ios/StockBar.xcodeproj -scheme StockBar \
  -destination 'platform=iOS Simulator,name=iPhone 17e' CODE_SIGNING_ALLOWED=NO test
```

Run these commands from the repository root. No package manager or project generator is required. The project uses Xcode's synchronized source folders and includes its shared scheme, unit tests, UI tests, and widget extension.

## Features

| Area | Native implementation |
| --- | --- |
| Overview | Whole-portfolio valuation, B3/US/bond/fund allocation, largest holdings, 3M–All return curves and up to three benchmarks |
| Stocks | Add/edit/remove holdings, quantity and average price, BRL valuation of US holdings, return charts with drag measurement, dividends/JCP and monthly payments chart |
| Bonds | Contract editor, business-day pricing, CDI/fixed/IPCA terms, gross/net values, IR/IOF, indexer allocation and maturity estimates |
| Funds | Holding editor, CNPJ autofill, CVM prices, statement prices for FIDC/FIP, purpose allocation, monthly/YTD/year returns |
| FGC | Conglomerate lookup from BCB, eligible exposures today/at maturity, per-group and overall limit usage |
| Comparison | CVM search by name/CNPJ/manager, up to six funds versus CDI, fund facts, fees/policy when published, monthly returns, size and flows |
| Open Finance | Keychain credentials, native bank authentication, add/reconnect/remove institutions, account/investment snapshots, automatic imports/reconciliation, batch selection with acquisition-price entry |
| Expenses | Month/search/review/income/exclusion filters, category overrides and merchant rules, foreign currency and installment handling, manual entries, deletion |
| Categories | Category editor, icon selection, bank keywords, always-visible native drag handles, category/total limits, suggested limits, threshold and large-purchase notifications |
| Insights | Year/month/category spending, budget reference, category trends, horizontally scrolling month grid |
| Bills | Upcoming/late items, card bills, loans, recurring payment detection, due-day overrides, manual paid status, hide/restore |
| AI | Apple Intelligence, own cloud API key, or a reachable Ollama server; read-only financial tools and inspectable lookup results |
| Settings | Benchmarks, light/dark/system, English/Portuguese, hide values, notification settings through iOS |
| Widget | Small/medium home-screen quick look with portfolio value, stock daily return and largest stock tickers; respects hide values |

## Visual identity

The app is installed as **Cymba Native**, with a black **Cy** lettermark on white rendered in the same bold system typography as the app. Regenerate the icon and launch marks with `swift ios/scripts/make-native-icon.swift` from the repository root. The Expo client keeps its original Cymba name and boat icon. `Views/CymbaTheme.swift` carries the exact light/dark tokens from `mobile/src/constants/theme.ts`: monochrome foreground tabs, blue `#2563eb` actions, white/near-black page backgrounds, gray surfaces, benchmark colors, 16-point page insets and compact cards. The four tabs and their SF Symbols follow `mobile/src/app/_layout.tsx`: Overview, Investments, Finances and Settings. Desktop-only extras (AI, Fund Comparison, price alerts and appearance controls) remain reachable under Settings → More.

Root headers and content cards follow the Expo screen hierarchy; detail pages keep compact native navigation. Categories retain native drag handles, stable IDs and background persistence. The Xcode scheme remains `StockBar`. The native app uses the separate `app.cymba.native` bundle ID, `group.app.cymba.native.shared` App Group, and exclusive `cymba-native://` URL scheme. The Expo app remains `app.cymba` with `cymba://`, so installing both does not replace either app or create ambiguous bank callbacks. Each app has its own local account and credentials; no data migration is performed.

## Architecture and persistence

`StockBar/Core` ports the macOS models, pricing, queries and stores. `Views` supplies phone navigation and forms; the desktop window, sidebar and menu bar layouts are replaced. The holding forms retain the desktop validations. `Platform` replaces desktop-only storage, subprocess ZIP extraction, notifications, authentication and local-model addressing. `StockBarWidget` is a separate WidgetKit extension.

The first launch starts an empty personal account. Portfolio files and Open Finance snapshots live in Application Support inside the app sandbox. Transactions, bills and public CVM data are cached separately. Market snapshots preserve the last downloaded prices offline. This is a separate account from both macOS and Expo; no cross-device synchronization or automatic data migration is implied.

Pluggy secrets and cloud API keys use the iOS Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility. They are excluded from the JSON records and widget data. A failed bank refresh retains its prior snapshot; destructive portfolio reconciliation waits for a complete refresh. Complete supported positions import automatically; missing rates, dates, costs or CNPJs are never guessed. Batch import can supply missing acquisition prices; other missing terms require checking the statement and adding the position manually.

The first successful sync requests transactions from the previous calendar year onward; later syncs refresh recent months. Older Expenses/Insights periods fetch on demand. Foreground freshness is six hours with a fifteen-minute failure retry floor. The background task requests a refresh no sooner than six hours; iOS chooses execution time. Price notifications and widget snapshots update when the app gets execution time, rather than monitoring continuously.

The bank widget runs in WKWebView; OAuth uses `ASWebAuthenticationSession` and `cymba-native://settings`. A redirect resumes the widget; only its success event imports the Item. See Apple's [authentication session documentation](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service). Configure the same redirect for your Pluggy application where required.

Cloud AI sends the question and tool outputs to the selected provider. Ollama runs on a separately configured computer, reached through Settings → AI → Server URL; an iPhone cannot run the desktop Ollama service. Prefer a trusted local network or HTTPS. Apple Intelligence stays on-device. The assistant's rules ship in `Resources/AI/rules.md`.

Desktop self-updates, DMG installation and keyboard/menu-bar controls have iPhone equivalents through app distribution, touch navigation and WidgetKit. Language changes take effect after restarting the app. The widget shows the stock sleeve's daily return, since a daily total-portfolio mark is not available for all asset classes.

## Validation

The unit suite verifies Cymba branding and the Expo light/dark palette, localized number entry, bond taxes and maturity, FGC eligibility, incomplete import rejection, acquisition-cost mapping, alert direction, merchant normalization and stored/deflated CVM ZIP entries. The UI suite verifies the four tab labels and captures every root screen in light and dark modes, drags a category using its native handle, verifies the order survives relaunch and the editor still opens, navigates the phone app, opens the bond editor, creates a manual expense, verifies it survives a relaunch, and opens AI/Settings. Category moves save once after dropping, skip transaction reclassification, and encode/write settings on a serial background queue.

Live Pluggy OAuth, institution-specific data, cloud provider responses, on-device Foundation Models, physical-device background scheduling and the installed home-screen widget require testing with a configured account/device. Simulator tests do not validate those services.
