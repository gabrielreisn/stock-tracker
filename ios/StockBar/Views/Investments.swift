import SwiftUI
import Charts

struct StocksScreen: View {
    @Environment(PortfolioStore.self) private var store
    @State private var editing: Holding?
    @State private var adding = false
    @State private var removing: Holding?
    @State private var range: ChartRange = .ytd
    @State private var sort = "Value"
    @State private var ascending = false
    private var holdings: [Holding] {
        store.holdings.sorted { a, b in
            if sort == "Ticker" { return ascending ? a.ticker < b.ticker : a.ticker > b.ticker }
            let av = metric(a), bv = metric(b)
            return ascending ? av < bv : av > bv
        }
    }
    private func metric(_ h: Holding) -> Double {
        switch sort {
        case "Shares": h.quantity
        case "Average price": h.averagePrice ?? 0
        case "Price": store.livePrice(h.ticker) ?? 0
        case "Gain": h.averagePrice.flatMap { avg in store.livePrice(h.ticker).map { $0 / avg - 1 } } ?? 0
        case "Today": store.tickerReturns[.day]?[h.ticker] ?? 0
        case "YTD": store.tickerReturns[.ytd]?[h.ticker] ?? 0
        default: h.weight * store.totalValue
        }
    }
    var body: some View {
        CymbaPage {
            CymbaCaption(text: "Personal account · saved on this device.")
            CymbaCard {
                Text("\(String(localized: "Stocks")) · \(store.holdings.count)").font(.system(size: 20, weight: .semibold))
                MoneyRow(title: String(localized: "Total value"), value: store.holdings.isEmpty ? "—" : store.totalValue.reais)
                CymbaCaption(text: "Quotes may be delayed. Pull to refresh. Missing prices are excluded from totals by showing —.")
                Button("Add stock") { adding = true }.buttonStyle(CymbaActionStyle())
            }
            CymbaCard {
                CymbaHeading(title: "Performance")
                RangePicker(range: $range, ranges: ChartRange.allCases)
                ReturnsChart(points: store.holdings.isEmpty ? [] : store.curves[range] ?? [], benchmarks: store.enabledBenchmarks)
            }
            CymbaHeading(title: "Holdings")
            CymbaChoices(values: ["Ticker", "Shares", "Average price", "Price", "Value", "Gain", "Today", "YTD"], selected: $sort)
            Button(ascending ? "Ascending ↑" : "Descending ↓") { ascending.toggle() }.buttonStyle(CymbaActionStyle())
            ForEach(holdings) { h in
                CymbaCard {
                    Text("\(h.ticker) · \(h.isUS ? "US" : "B3")").font(.system(size: 20, weight: .semibold))
                    if let name = h.name { CymbaCaption(text: LocalizedStringKey(name)) }
                    MoneyRow(title: String(localized: "Shares"), value: h.quantity.quantity)
                    MoneyRow(title: String(localized: "Average price"), value: h.averagePrice?.price(for: h.ticker) ?? "—")
                    MoneyRow(title: String(localized: "Price"), value: store.livePrice(h.ticker)?.price(for: h.ticker) ?? "—")
                    MoneyRow(title: String(localized: "Value"), value: (h.weight * store.totalValue).reais)
                    MoneyRow(title: String(localized: "Gain"), value: h.averagePrice.flatMap { avg in store.livePrice(h.ticker).map { ($0 / avg - 1).signedPercent } } ?? "—")
                    MoneyRow(title: String(localized: "Today"), value: store.tickerReturns[.day]?[h.ticker]?.signedPercent ?? "—")
                    MoneyRow(title: "YTD", value: store.tickerReturns[.ytd]?[h.ticker]?.signedPercent ?? "—")
                    HStack(spacing: 12) {
                        Button("Edit stock") { editing = h }.buttonStyle(CymbaActionStyle())
                        Button("Remove", role: .destructive) { removing = h }.buttonStyle(CymbaActionStyle())
                    }
                }
            }
            if holdings.isEmpty { CymbaCard { CymbaCaption(text: "No stocks yet. Add a ticker and quantity.") } }
            CymbaCard {
                Text("\(String(localized: "Dividends")) · \(Calendar.current.component(.year, from: .now))").font(.system(size: 20, weight: .semibold))
                if store.dividends.isEmpty { CymbaCaption(text: "No dividend events available for this year.") }
                else {
                    Chart(store.dividends) { d in BarMark(x: .value("Month", DayKey.date(d.paymentDay ?? d.recordDay), unit: .month), y: .value("Amount", d.amount)).foregroundStyle(CymbaTheme.accent) }.frame(height: 110)
                    ForEach(store.dividends) { d in MoneyRow(title: "\(d.ticker) · \(d.kind.label)", detail: DayKey.date(d.day).formatted(date: .abbreviated, time: .omitted), value: d.amount.reais) }
                }
            }
        }.cymbaList().cymbaNavigationTitle("Stocks")
        .sheet(isPresented: $adding) { StockForm(ticker: "", quantity: nil, averagePrice: nil).presentationDragIndicator(.visible) }
        .sheet(item: $editing) { StockForm(ticker: $0.ticker, quantity: $0.quantity, averagePrice: $0.averagePrice).presentationDragIndicator(.visible) }
        .confirmationDialog("Remove stock?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let h = removing { store.removeStock(h.ticker) }; removing = nil }
        }
        .refreshable { await store.refresh() }
    }
}

struct BondsScreen: View {
    @Environment(PortfolioStore.self) private var store
    @State private var editing: Bond?
    @State private var ascending = true
    @State private var sort = "Matures"
    private func newBond() -> Bond { Bond(kind: .cdb, issuer: "", code: "", issueDay: DayKey.from(.now), maturityDay: DayKey.addMonths(DayKey.from(.now), 12), indexer: .cdi, rate: 100, quantity: 1) }
    private func sorted(_ bonds: [Bond]) -> [Bond] {
        let pricer = store.bondPricer
        return bonds.sorted { a,b in
            if sort == "Issuer" { return ascending ? a.issuer < b.issuer : a.issuer > b.issuer }
            func key(_ b: Bond) -> Double {
                let value = pricer.value(b)
                switch sort {
                case "Issued": return Double(b.issueDay)
                case "Matures": return Double(b.maturityDay)
                case "Rate": return b.rate
                case "Quantity": return b.quantity
                case "Gross value": return value.gross
                case "Income tax": return value.incomeTax + value.iof
                case "Net value": return value.net
                default: return value.gain / max(b.invested, 1)
                }
            }
            return ascending ? key(a) < key(b) : key(a) > key(b)
        }
    }
    var body: some View {
        CymbaPage {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Personal account").font(.system(size: 14)); CymbaCaption(text: "Changes are saved on this device.") }
                Spacer()
                Button("Add bond") { editing = newBond() }.buttonStyle(CymbaActionStyle(primary: true)).fixedSize(horizontal: true, vertical: false)
            }
            if store.bonds.isEmpty {
                CymbaCard { CymbaHeading(title: "No bonds yet"); CymbaCaption(text: "Add CDBs, LCAs and other fixed income with their rate and dates.") }
            } else {
                CymbaCard {
                    CymbaHeading(title: "Portfolio summary")
                    let valuations = store.bonds.map { store.bondPricer.value($0) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        CymbaMetric(label: "Invested", value: store.bonds.reduce(0) { $0 + $1.invested }.reais)
                        CymbaMetric(label: "Gross value", value: valuations.reduce(0) { $0 + $1.gross }.reais)
                        CymbaMetric(label: "Income tax + IOF", value: valuations.reduce(0) { $0 + $1.incomeTax + $1.iof }.reais)
                        CymbaMetric(label: "Net value", value: valuations.reduce(0) { $0 + $1.net }.reais)
                    }
                }
                HStack { CymbaHeading(title: "Holdings"); Spacer(); Button(ascending ? "Ascending ↑" : "Descending ↓") { ascending.toggle() }.font(.system(size: 14)).foregroundStyle(CymbaTheme.link) }
                CymbaChoices(values: ["Issuer", "Issued", "Matures", "Rate", "Quantity", "Gross value", "Income tax", "Net value", "Return"], selected: $sort)
                ForEach(BondKind.allCases) { kind in
                    let bonds = sorted(store.bonds.filter { $0.kind == kind })
                    if !bonds.isEmpty {
                        CymbaCard {
                            HStack { Text(kind.rawValue).font(.system(size: 20, weight: .semibold)); Spacer(); if kind.isTaxExempt { CymbaCaption(text: "Tax exempt") } }
                            ForEach(bonds) { b in
                                Button { editing = b } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        MoneyRow(title: b.issuer, detail: b.code, value: "›")
                                        Text("\(b.indexer.describe(b.rate)) · \(b.quantity.quantity) × \(b.unitPrice.reais)").font(.system(size: 14))
                                        Text("\(String(localized: "Issued")): \(DayKey.date(b.issueDay).formatted(date: .abbreviated, time: .omitted))").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                                        Text("\(String(localized: "Matures")): \(DayKey.date(b.maturityDay).formatted(date: .abbreviated, time: .omitted))").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                                        let v = store.bondPricer.value(b)
                                        MoneyRow(title: String(localized: "Gross value"), value: v.gross.reais)
                                        MoneyRow(title: String(localized: "Income tax + IOF"), value: (v.incomeTax + v.iof).reais)
                                        MoneyRow(title: String(localized: "Net value"), value: v.net.reais)
                                        MoneyRow(title: String(localized: "Return"), value: (v.gain / max(b.invested, 1)).signedPercent)
                                    }.padding(.vertical, 8)
                                }.buttonStyle(.plain)
                                Divider().overlay(CymbaTheme.selected)
                            }
                            MoneyRow(title: String(localized: "Total net"), value: bonds.reduce(0) { $0 + store.bondPricer.value($1).net }.reais)
                        }
                    }
                }
                CymbaCard {
                    CymbaHeading(title: "Allocation by indexer")
                    ForEach(BondIndexer.allCases) { indexer in
                        MoneyRow(title: indexer.label, value: store.bonds.filter { $0.indexer == indexer }.reduce(0) { $0 + store.bondPricer.value($1).gross }.reais)
                    }
                }
            }
        }.cymbaList().cymbaNavigationTitle("Bonds")
        .sheet(item: $editing) { BondForm(bond: $0).presentationDragIndicator(.visible) }
    }
}

struct FundsScreen: View {
    @Environment(FundStore.self) private var funds
    @State private var editing: FundHolding?
    @State private var query = ""
    @State private var sort = "Gross value"
    @State private var ascending = false
    private var rows: [FundHolding] {
        funds.holdings.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.cnpj.contains(query.filter(\.isNumber)) && !query.filter(\.isNumber).isEmpty }.sorted { a,b in
            if sort == "Name" { return ascending ? a.name < b.name : a.name > b.name }
            let av = sort == "Shares" ? a.quantity : funds.value(a)?.gross ?? 0
            let bv = sort == "Shares" ? b.quantity : funds.value(b)?.gross ?? 0
            return ascending ? av < bv : av > bv
        }
    }
    var body: some View {
        CymbaPage {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Personal account").font(.system(size: 14)); CymbaCaption(text: "Changes are saved on this device.") }
                Spacer()
                Button("Add fund") { editing = FundHolding(cnpj: "", name: "", kind: .fif, quantity: 0, taxExempt: false) }.buttonStyle(CymbaActionStyle(primary: true)).fixedSize(horizontal: true, vertical: false)
            }
            CymbaCard {
                CymbaHeading(title: "Portfolio summary")
                CymbaMetric(label: "Gross value", value: funds.holdings.reduce(0) { $0 + (funds.value($1)?.gross ?? 0) }.reais)
                CymbaCaption(text: "Values use the latest bank statement. Returns require CVM history. Values are gross, before income tax.")
            }
            TextField("Search funds", text: $query).textFieldStyle(CymbaInputStyle())
            CymbaChoices(values: ["Name", "Shares", "Gross value"], selected: $sort)
            Button(ascending ? "Ascending ↑" : "Descending ↓") { ascending.toggle() }.buttonStyle(CymbaActionStyle())
            ForEach(rows) { h in
                NavigationLink { FundPositionScreen(holding: h) } label: {
                    CymbaCard {
                        Text(h.name).font(.system(size: 16, weight: .semibold))
                        CymbaCaption(text: LocalizedStringKey("\(CVM.formatCNPJ(h.cnpj)) · \(h.kind.label) · \(String(localized: h.taxExempt ? "Tax exempt" : "Taxable"))"))
                        Text(funds.purpose(of: h).label).font(.system(size: 13)).foregroundStyle(CymbaTheme.link)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            CymbaMetric(label: "Shares", value: h.quantity.shares)
                            CymbaMetric(label: "Gross value", value: funds.value(h)?.gross.reais ?? "—")
                            CymbaMetric(label: "Share price", value: funds.value(h)?.price.shares ?? "—")
                            CymbaMetric(label: "Price date", value: funds.value(h).map { DayKey.date($0.day).formatted(date: .abbreviated, time: .omitted) } ?? "—")
                        }
                        HStack { CymbaMetric(label: "Last month", value: funds.value(h)?.month?.signedPercent ?? "—"); CymbaMetric(label: "Year to date", value: funds.value(h)?.ytd?.signedPercent ?? "—") }
                        Text("Edit fund →").font(.system(size: 13)).foregroundStyle(CymbaTheme.link)
                    }
                }.buttonStyle(.plain)
            }
            if rows.isEmpty { CymbaCard { CymbaCaption(text: "No funds yet") } }
            CymbaCard {
                CymbaHeading(title: "Allocation by purpose")
                ForEach(FundPurpose.allCases) { purpose in
                    let amount = funds.holdings.filter { funds.purpose(of: $0) == purpose }.reduce(0) { $0 + (funds.value($1)?.gross ?? 0) }
                    if amount > 0 { MoneyRow(title: purpose.label, value: amount.reais) }
                }
            }
        }.cymbaList().cymbaNavigationTitle("Funds")
        .sheet(item: $editing) { FundHoldingForm(holding: $0).presentationDragIndicator(.visible) }
        .refreshable { funds.loadHoldings() }
    }
}

struct FundPositionScreen: View {
    @Environment(FundStore.self) private var funds
    let holding: FundHolding
    @State private var edit = false
    var body: some View {
        List {
            Section {
                Text(holding.name).font(.headline)
                Text(CVM.formatCNPJ(holding.cnpj)).textSelection(.enabled)
                MoneyRow(title: String(localized: "Shares"), value: holding.quantity.shares)
                MoneyRow(title: String(localized: "Purpose"), value: funds.purpose(of: holding).label)
                if let v = funds.value(holding) {
                    MoneyRow(title: String(localized: "Gross value"), value: v.gross.reais)
                    MoneyRow(title: String(localized: "Share price"), detail: DayKey.date(v.day).formatted(date: .abbreviated, time: .omitted), value: v.price.reais)
                    MoneyRow(title: "1M", value: v.month?.signedPercent ?? "—")
                    MoneyRow(title: "YTD", value: v.ytd?.signedPercent ?? "—")
                    MoneyRow(title: "1Y", value: v.year?.signedPercent ?? "—")
                }
            }
            Button("Edit") { edit = true }
        }.cymbaList().cymbaNavigationTitle("Fund details")
        .sheet(isPresented: $edit) { FundHoldingForm(holding: holding) }
    }
}

struct FGCScreen: View {
    @Environment(PortfolioStore.self) private var store
    @State private var conglomerates: [String: Conglomerate] = [:]
    private var groups: [(String, [Bond])] {
        Dictionary(grouping: store.bonds.filter { $0.kind.isFGCCovered && $0.maturityDay >= DayKey.from(.now) }) { b in
            if let cnpj = b.issuerCNPJ { return conglomerates[String(cnpj.prefix(8))]?.name ?? String(cnpj.prefix(8)) }
            return b.issuer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }.sorted { $0.key < $1.key }
    }
    var body: some View {
        CymbaPage {
            Text("Personal account").font(.system(size: 14))
            CymbaCaption(text: "Changes are saved on this device.")
            CymbaCaption(text: "The FGC guarantees up to R$ 250 mil per CPF in each institution or financial conglomerate, and R$ 1 milhão per CPF in total every four years. It covers CDB, LC, LCI and LCA (and deposits), not CRI, CRA or debentures.")
            CymbaCard {
                CymbaCaption(text: "Exposure by financial conglomerate")
                let covered = groups.reduce(0.0) { total, g in total + min(250000, g.1.reduce(0) { $0 + store.bondPricer.value($1).gross }) }
                let above = groups.reduce(0.0) { total, g in total + max(0, g.1.reduce(0) { $0 + store.bondPricer.value($1).gross } - 250000) }
                MoneyRow(title: String(localized: "Guaranteed"), value: covered.reais)
                MoneyRow(title: String(localized: "Above the limit"), value: above.reais)
                MoneyRow(title: String(localized: "Overall limit used"), value: (covered / 1_000_000).percent)
                CymbaCaption(text: "Of R$ 1 million per CPF every four years; prior claims are not tracked here.")
            }
            CymbaCard { CymbaHeading(title: "Reading the bars"); CymbaCaption(text: "Filled bar: value today · circle: estimated maturity value · vertical line: R$ 250,000 limit.") }
            if groups.isEmpty { CymbaCard { CymbaHeading(title: "No active CDB, LC, LCI or LCA in Bonds.") } }
            ForEach(groups, id: \.0) { key, bonds in
                CymbaCard {
                    Text(key).font(.system(size: 20, weight: .semibold))
                    let gross = bonds.reduce(0) { $0 + store.bondPricer.value($1).gross }
                    let maturity = bonds.reduce(0) { $0 + (store.bondPricer.value($1).atMaturity ?? store.bondPricer.value($1).gross) }
                    ProgressView(value: min(gross / 250000, 1)).tint(gross > 250000 ? CymbaTheme.danger : gross > 200000 ? CymbaTheme.warning : CymbaTheme.success)
                    MoneyRow(title: String(localized: "Gross value"), value: gross.reais)
                    MoneyRow(title: String(localized: "Headroom"), value: max(0, 250000 - gross).reais)
                    MoneyRow(title: String(localized: "At maturity (est.)"), value: maturity.reais)
                    ForEach(bonds) { b in
                        Text("\(b.kind.rawValue) · \(b.issuer)").font(.system(size: 14))
                        if b.issuerCNPJ == nil { Text("CNPJ unknown: edit the bonds or sync Open Finance").font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
                    }
                }
            }
            let uncovered = store.bonds.filter { !$0.kind.isFGCCovered }
            if !uncovered.isEmpty { CymbaCard { CymbaHeading(title: "Not covered by the FGC"); ForEach(uncovered) { MoneyRow(title: $0.issuer, detail: $0.kind.rawValue, value: store.bondPricer.value($0).gross.reais) } } }
        }.cymbaNavigationTitle("FGC Watcher").task { conglomerates = await BCBConglomerates.load() }
    }
}

struct ComparisonScreen: View {
    @Environment(FundStore.self) private var funds
    @State private var query = ""
    var body: some View {
        @Bindable var funds = funds
        List {
            if case .loading = funds.indexState { ProgressView("Downloading CVM registry…") }
            if case .failed(let message) = funds.indexState { Text(message).foregroundStyle(.orange); Button("Retry") { funds.start() } }
            Section("Compare up to six funds") {
                Picker("Range", selection: $funds.range) { ForEach(FundRange.allCases) { Text($0.rawValue).tag($0) } }
                if funds.isLoading { ProgressView("\(funds.progress.done) / \(funds.progress.total)") }
                Chart {
                    ForEach(funds.points) { p in
                        ForEach(funds.selected) { f in
                            if let v = p.returns[f.id] { LineMark(x: .value("Date", p.date), y: .value("Return", v)).foregroundStyle(by: .value("Fund", f.fund.name)) }
                        }
                        if let cdi = p.cdi { LineMark(x: .value("Date", p.date), y: .value("Return", cdi)).foregroundStyle(by: .value("Fund", "CDI")) }
                    }
                }.frame(height: 240)
                if let error = funds.error { Text(error).font(.caption).foregroundStyle(.orange) }
                ForEach(funds.selected) { f in
                    NavigationLink { FactSheetScreen(fund: f.fund) } label: {
                        MoneyRow(title: f.fund.name, detail: f.fund.formattedCNPJ, value: funds.stats[f.id]?.totalReturn.signedPercent ?? "—")
                    }.swipeActions { Button("Remove", role: .destructive) { funds.remove(f) } }
                }
            }
            Section("Search by name, CNPJ or manager") {
                ForEach(funds.search(query)) { f in
                    Button { funds.add(f); query = "" } label: {
                        VStack(alignment: .leading) { Text(f.name); Text(f.formattedCNPJ).font(.caption).foregroundStyle(CymbaTheme.secondary) }
                    }.disabled(funds.selected.count >= FundStore.maxSelected)
                }
            }
        }.cymbaList().cymbaNavigationTitle("Fund Comparison").searchable(text: $query).task { funds.start() }
    }
}

struct FactSheetScreen: View {
    @Environment(FundStore.self) private var funds
    let fund: FundInfo
    @State private var details: FundDetails?
    @State private var lamina: Lamina?
    var body: some View {
        List {
            Section {
                Text(fund.name).font(.headline)
                Text(fund.formattedCNPJ).textSelection(.enabled)
                Text(fund.manager ?? "—")
                if let d = details {
                    LabeledContent("Category", value: d.cvmClass ?? "—")
                    LabeledContent("Benchmark", value: d.benchmark ?? "—")
                    LabeledContent("Inception", value: d.inception ?? "—")
                    LabeledContent("Audience", value: d.audience ?? "—")
                }
                if let stats = funds.stats[fund.id] {
                    MoneyRow(title: String(localized: "Return"), value: stats.totalReturn.signedPercent)
                    MoneyRow(title: String(localized: "Volatility"), value: stats.volatility?.percent ?? "—")
                    MoneyRow(title: String(localized: "Max drawdown"), value: stats.maxDrawdown.percent)
                }
            }
            if let latest = funds.summaries[fund.id]?.last?.summary {
                Section("Net assets and flows") {
                    MoneyRow(title: String(localized: "Net assets"), value: latest.netAssets.fundSize)
                    LabeledContent("Shareholders", value: latest.shareholders.formatted())
                    MoneyRow(title: String(localized: "Net flow"), value: (latest.inflow - latest.outflow).fundSize)
                }
            }
            if let lamina {
                Section("CVM fact sheet") {
                    Text(DayKey.date(lamina.date), style: .date).font(.caption)
                    ForEach(["OBJETIVO", "POLIT_INVEST", "TAXA_ADM", "TAXA_PERFM", "APLIC_MIN", "RESGATE_MIN"], id: \.self) { key in
                        if let text = lamina.text(key) { LabeledContent(LocalizedStringKey(["OBJETIVO": "Objective", "POLIT_INVEST": "Investment policy", "TAXA_ADM": "Management fee", "TAXA_PERFM": "Performance fee", "APLIC_MIN": "Minimum investment", "RESGATE_MIN": "Minimum redemption"][key] ?? key), value: text) }
                    }
                    ForEach(Array(lamina.portfolio.enumerated()), id: \.offset) { _, slice in
                        MoneyRow(title: slice.asset, value: (slice.percent / 100).percent)
                    }
                }
            }
            ForEach(funds.monthlyReturns(fund.id)) { year in
                Section(String(year.year)) {
                    ForEach(year.months.keys.sorted(), id: \.self) { m in MoneyRow(title: String(m), value: year.months[m]?.signedPercent ?? "—") }
                }
            }
        }.cymbaList().cymbaNavigationTitle("Fact sheet").task { async let d = funds.details(for: fund.id); async let l = CVM.lamina(for: fund); details = await d; lamina = await l }
    }
}

struct PriceAlertsScreen: View {
    @Environment(PortfolioStore.self) private var store
    @State private var ticker = ""
    @State private var target = ""
    @State private var kind = TradeKind.buy
    var body: some View {
        List {
            Section("New alert") {
                TextField("Ticker", text: $ticker).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Target price", text: $target).keyboardType(.decimalPad)
                Picker("Condition", selection: $kind) { Text("at or below").tag(TradeKind.buy); Text("at or above").tag(TradeKind.sell) }
                Button("Add alert") {
                    guard let price = parseNumber(target), price > 0 else { return }
                    store.addAlert(PriceAlert(ticker: ticker.uppercased().trimmingCharacters(in: .whitespaces), target: price, kind: kind))
                    ticker = ""; target = ""
                    Task { _ = await AlertNotifier.shared.authorize() }
                }.disabled(ticker.trimmingCharacters(in: .whitespaces).isEmpty || (parseNumber(target) ?? 0) <= 0)
            }
            Section("Price alerts") {
                ForEach(store.alerts) { alert in
                    Toggle(isOn: Binding(get: { alert.isEnabled }, set: { store.setAlert(alert, enabled: $0) })) {
                        Text(alert.ticker)
                        Text("\(alert.condition) \(alert.target.price(for: alert.ticker))").font(.caption)
                        if let date = alert.triggeredAt { Text(date, style: .date).font(.caption) }
                    }.swipeActions { Button("Delete", role: .destructive) { store.deleteAlert(alert) } }
                }
            }
            Text("Price alerts are checked when market data refreshes. Background delivery is scheduled by iOS.").font(.caption).foregroundStyle(CymbaTheme.secondary)
        }.cymbaList().cymbaNavigationTitle("Price alerts")
    }
}
