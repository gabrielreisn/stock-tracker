# StockBar

A native macOS menu bar app (SwiftUI, no Electron) that tracks a Brazilian and US stock portfolio
against CDI, IPCA, IPCA+5%, the S&P 500 and IFIX.

## Install

Download the latest `StockBar-<version>.dmg` from [Releases](../../releases), open it and drag StockBar to Applications.
The app isn't notarized yet: on first launch, allow it in **System Settings → Privacy & Security → Open Anyway**.
Requires macOS 15+ (Apple Silicon or Intel).

## Develop

```sh
./build.sh            # universal build/StockBar.app
./build.sh --install  # copy to ~/Applications and launch
./build.sh --dmg      # package build/StockBar-<version>.dmg
swift scripts/make-icon.swift  # regenerate Resources/AppIcon.icns
```

## Release

Push a version tag and GitHub Actions builds the DMG and publishes the release:

```sh
git tag v1.1.0 && git push origin v1.1.0
```

## How it works

- **Trades** are buy/sell, ticker, date and quantity, stored in `~/Library/Application Support/StockBar/trades.json`.
  The quantities you hold today define the portfolio.
- **The curve** shows the current portfolio (today's quantities) held through the whole range: 1D, 3M, YTD, or All (since 01/01/2010).
  Each session's return weights stocks by their value at the previous close. Stocks that weren't listed yet are left out until they were.
- **Prices** come from Yahoo Finance (`PETR4` → `PETR4.SA`; fractional `PETR4F` maps to `PETR4`).
  Daily prices are adjusted closes, so dividends, JCP and splits are included (total return); they reload every 6 hours.
  1D uses 5-minute prices against the previous close. Prices refresh every 5 minutes.
- **Benchmarks** come from Banco Central's SGS API: CDI is series 12 (daily rate) and IPCA is series 433 (monthly rate).
  IPCA is pro-rated by calendar days within a month, and months not yet published count as 0%.
  The API is flaky with long ranges, so it's fetched a year at a time with retries.
  It's cached in `cdi-cache.json` and `ipca-cache.json` next to the trades; only recent weeks are re-fetched.
- Every range starts at 0% at the close before it begins (for YTD, the last close of last year).
