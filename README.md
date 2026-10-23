<img width="1102" height="1604" alt="CleanShot 2026-10-19 at 21 11 21@2x" src="https://github.com/user-attachments/assets/093c2e46-a93e-4083-8a21-2c63fe585407" />


# StockBar

A native macOS app (SwiftUI, no Electron) that tracks a Brazilian investment portfolio — stocks (B3 and US),
bonds and funds — against CDI, IPCA, IPCA+6%, the S&P 500, IFIX and IBOV. It opens as a window, with a
menu bar widget for a quick look.

## Install

Download the latest `StockBar-<version>.dmg` from [Releases](../../releases), open it and drag StockBar to Applications.
The app isn't notarized yet: on first launch, allow it in **System Settings → Privacy & Security → Open Anyway**.
Requires macOS 15+ (Apple Silicon or Intel).

## What's in it

- **Overview** — the whole portfolio: value by asset class, allocation (B3 stocks, US stocks, bonds, funds),
  largest positions, and one return curve for everything against the benchmarks (3M, YTD, 1Y).
- **Stocks** — the performance chart (drag across it to measure a period), holdings with quantity and average
  price, and this year's dividends and JCP with a monthly chart.
- **Bonds** — CDBs, LCAs and other fixed income valued from their terms, with income tax, allocation by indexer
  and maturities.
- **Funds** — fund holdings at CVM's latest share price, returns, and allocation by purpose (Selic, credit, inflation…).
- **FGC Watcher** — exposure per financial conglomerate against the FGC's R$ 250 mil per-institution limit and
  R$ 1 milhão overall, today and estimated at maturity.
- **Fund Comparison** — search CVM's ~26k funds by name, CNPJ or manager, compare up to six against CDI, and open
  a fact sheet for each.
- **Open Finance** — investments and accounts pulled through [Meu Pluggy](https://meu.pluggy.ai), checked against
  what StockBar tracks, with one click to add or update a position.
- **Menu bar widget** — today's chart and holdings, plus price alerts that send a notification when a ticker reaches a target.

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
git tag v2.0.0 && git push origin v2.0.0
```

## How it works

Your data lives in `~/Library/Application Support/StockBar/` (`trades.json`, `bonds.json`, `fund-holdings.json`,
`alerts.json`); downloaded market data is cached in `~/Library/Caches/StockBar/`.

- **Stocks** are a ticker, a quantity and an optional average price. The quantities you hold today define the portfolio:
  the curve holds them through the whole range, each session's return weighting stocks by their value at the previous close.
- **Prices** come from Yahoo Finance (`PETR4` → `PETR4.SA`), as adjusted closes so dividends, JCP and splits are included
  (total return). US stocks are converted at each day's USD/BRL. A market that hasn't traded today shows "—" for 1D.
- **Benchmarks**: CDI (series 12) and IPCA (series 433) from Banco Central's SGS API, cached and refreshed incrementally;
  IFIX history from B3; S&P 500 (total return) and IBOV from Yahoo.
- **Dividends** for B3 companies come from B3's announcements (dividend vs JCP, record and payment dates); FIIs and US
  stocks use Yahoo's ex-dividend events. Amounts are gross, for the quantity held today.
- **Bonds** are priced like banks mark them: business days over 252 with ANBIMA holidays; CDI compounded daily at the
  contracted share; IPCA stepped on the issue day's monthly anniversary with the latest index published before each
  period ends. Income tax follows the regressive table; LCA, LCI, CRI, CRA and incentivized debentures are exempt.
- **Funds** use CVM's open data: daily reports (informe diário) for regular funds, the monthly FIDC report for receivables
  funds, and the statement price for FIPs. The fund registry, fact sheets (lâmina) and daily reports also power Fund Comparison.
- **FGC Watcher** groups issuers by their prudential conglomerate in Banco Central's IF.data, since institutions of one
  conglomerate share a single limit.
- **Open Finance** uses your own Pluggy application: the client secret is stored in the macOS Keychain, and each
  connection's item ID is added in Settings (Meu Pluggy can't list connections through the API).
