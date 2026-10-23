import SwiftUI

enum StockSort: String {
    case ticker, shares, average, price, value, gain, today, ytd
}

/// Every stock held, with adding, editing (quantity and average price) and removal.
struct StockHoldingsSection: View {
    @Environment(PortfolioStore.self) private var store
    @AppStorage("stockSort") private var sort: StockSort = .value
    @AppStorage("stockSortAscending") private var ascending = false

    @State private var ticker = ""
    @State private var quantity = ""
    @State private var price = ""
    @State private var checking = false
    @State private var error: String?
    @State private var editing: String?
    @State private var editQuantity = ""
    @State private var editPrice = ""
    @State private var pendingDelete: String?
    @FocusState private var editFocused: Bool

    private enum Width {
        static let shares: CGFloat = 96, average: CGFloat = 96, price: CGFloat = 96, value: CGFloat = 112
        static let gain: CGFloat = 116, today: CGFloat = 64, ytd: CGFloat = 72, actions: CGFloat = 56
    }

    private var normalizedTicker: String { ticker.trimmingCharacters(in: .whitespaces).uppercased() }
    private var newQuantity: Double? { parseNumber(quantity).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Holdings").font(.title2.weight(.semibold))
                Text("\(store.holdings.count) stocks").foregroundStyle(.secondary)
                Spacer()
                addForm
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            summary
            VStack(spacing: 0) {
                header
                Divider()
                if store.holdings.isEmpty {
                    Text("No stocks yet. Add a ticker and quantity above.").foregroundStyle(.secondary).padding(24)
                } else {
                    let rows = sorted(store.holdings)
                    ForEach(rows) { h in
                        row(h)
                        if h.id != rows.last?.id { Divider().padding(.horizontal, 14) }
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
        }
    }

    /// Cost and unrealized gain in reais, over B3 stocks with an average price
    /// (US stocks' cost would need the dollar on each purchase day).
    @ViewBuilder
    private var summary: some View {
        let priced = store.holdings.filter { !$0.isUS && $0.averagePrice != nil }
        let cost = priced.reduce(0) { $0 + $1.quantity * $1.averagePrice! }
        let value = priced.reduce(0) { $0 + $1.quantity * (store.livePrice($1.ticker) ?? 0) }
        if cost > 0 {
            HStack(spacing: 18) {
                Text("B3 stocks: ").foregroundStyle(.secondary) + Text("cost \(cost.reais)")
                Text("value \(value.reais)")
                Text("gain \(value - cost >= 0 ? "+" : "")\((value - cost).reais) (\((value / cost - 1).signedPercent))")
                    .foregroundStyle((value - cost).gainColor)
                    .fontWeight(.semibold)
            }
            .font(.callout.monospacedDigit())
        }
    }

    // MARK: - Adding

    private var addForm: some View {
        HStack(spacing: 8) {
            TextField("Ticker", text: $ticker, prompt: Text("PETR4"))
                .frame(width: 100)
            TextField("Quantity", text: $quantity, prompt: Text("Qty"))
                .frame(width: 80)
            TextField("Average price", text: $price, prompt: Text("Avg price"))
                .frame(width: 90)
                .onSubmit(add)
            Button {
                add()
            } label: {
                if checking { ProgressView().controlSize(.small) } else { Label("Add", systemImage: "plus") }
            }
            .disabled(normalizedTicker.isEmpty || newQuantity == nil || checking)
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: ticker) { error = nil }
    }

    /// Checks the ticker exists before saving. Adding to a stock already held sums the shares and
    /// averages the prices.
    private func add() {
        guard !normalizedTicker.isEmpty, let q = newQuantity, !checking else { return }
        let symbol = normalizedTicker
        let paid = parseNumber(price).flatMap { $0 > 0 ? $0 : nil }
        checking = true
        Task {
            defer { checking = false }
            guard (try? await MarketData.intraday(for: symbol)) != nil else {
                error = "Couldn't find \(symbol)"
                return
            }
            if let held = store.holdings.first(where: { $0.ticker == symbol }) {
                let average: Double? = switch (held.averagePrice, paid) {
                case let (old?, new?): (held.quantity * old + q * new) / (held.quantity + q)
                case let (old, new): old ?? new
                }
                store.setQuantity(symbol, to: held.quantity + q, averagePrice: average)
            } else {
                store.add(Trade(ticker: symbol, kind: .buy, date: .now, quantity: q, price: paid))
            }
            ticker = ""
            quantity = ""
            price = ""
        }
    }

    // MARK: - Table

    private var header: some View {
        HStack(spacing: 10) {
            column("Stock", .ticker, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
            column("Shares", .shares).frame(width: Width.shares, alignment: .trailing)
            column("Avg price", .average).frame(width: Width.average, alignment: .trailing)
            column("Price", .price).frame(width: Width.price, alignment: .trailing)
            column("Value", .value).frame(width: Width.value, alignment: .trailing)
            column("Gain", .gain).frame(width: Width.gain, alignment: .trailing)
            column("Today", .today).frame(width: Width.today, alignment: .trailing)
            column("YTD", .ytd).frame(width: Width.ytd, alignment: .trailing)
            Text("").frame(width: Width.actions)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    private func column(_ title: String, _ key: StockSort, ascendingFirst: Bool = false) -> some View {
        SortHeader(title: title, key: key, sort: $sort, ascending: $ascending, ascendingFirst: ascendingFirst)
    }

    /// Prices are in each stock's own currency, so sorting by price or average mixes reais and dollars, as the columns do.
    private func sorted(_ rows: [Holding]) -> [Holding] {
        switch sort {
        case .ticker: rows.sorted(byText: { $0.ticker }, ascending: ascending)
        case .shares: rows.sorted(by: { $0.quantity }, ascending: ascending)
        case .average: rows.sorted(by: { $0.averagePrice }, ascending: ascending)
        case .price: rows.sorted(by: { store.livePrice($0.ticker) }, ascending: ascending)
        case .value: rows.sorted(by: { $0.weight }, ascending: ascending)
        case .gain: rows.sorted(by: { h in h.averagePrice.flatMap { avg in store.livePrice(h.ticker).map { $0 / avg - 1 } } }, ascending: ascending)
        case .today: rows.sorted(by: { store.tickerReturns[.day]?[$0.ticker] }, ascending: ascending)
        case .ytd: rows.sorted(by: { store.tickerReturns[.ytd]?[$0.ticker] }, ascending: ascending)
        }
    }

    private func row(_ h: Holding) -> some View {
        let today = store.tickerReturns[.day]?[h.ticker]
        let ytd = store.tickerReturns[.ytd]?[h.ticker]
        let live = store.livePrice(h.ticker)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(h.ticker).fontWeight(.semibold)
                    if h.isUS {
                        Text("US").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                    }
                }
                if let name = h.name { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if editing == h.ticker {
                editFields(h)
            } else {
                Button { startEdit(h) } label: { Text(h.quantity.quantity) }
                    .buttonStyle(.plain)
                    .frame(width: Width.shares, alignment: .trailing)
                    .help("Click to edit")
                Button { startEdit(h) } label: {
                    Text(h.averagePrice?.price(for: h.ticker) ?? "—").foregroundStyle(h.averagePrice == nil ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: Width.average, alignment: .trailing)
                .help("Click to edit")
            }

            Text(live?.price(for: h.ticker) ?? "—").frame(width: Width.price, alignment: .trailing)
            Text(store.totalValue > 0 ? (h.weight * store.totalValue).reais : "—").fontWeight(.medium)
                .frame(width: Width.value, alignment: .trailing)
            gain(h, live: live).frame(width: Width.gain, alignment: .trailing)
            Text(today?.signedPercent ?? "—").foregroundStyle((today ?? 0).gainColor).frame(width: Width.today, alignment: .trailing)
            Text(ytd?.signedPercent ?? "—").foregroundStyle((ytd ?? 0).gainColor).frame(width: Width.ytd, alignment: .trailing)

            HStack(spacing: 10) {
                if pendingDelete == h.ticker {
                    Button("Remove") { store.removeStock(h.ticker); pendingDelete = nil }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                } else {
                    Button { startEdit(h) } label: { Image(systemName: "pencil") }
                        .help("Edit quantity and average price")
                    Button { pendingDelete = h.ticker; editing = nil } label: { Image(systemName: "trash") }
                        .help("Remove \(h.ticker)")
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .frame(width: Width.actions, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: PageLayout.rowHeight)
    }

    /// Against the average price, in the stock's own currency.
    @ViewBuilder
    private func gain(_ h: Holding, live: Double?) -> some View {
        if let average = h.averagePrice, average > 0, let live {
            let change = live / average - 1
            VStack(alignment: .trailing, spacing: 1) {
                Text(change.signedPercent).foregroundStyle(change.gainColor)
                Text(((live - average) * h.quantity).price(for: h.ticker))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    private func editFields(_ h: Holding) -> some View {
        HStack(spacing: 6) {
            TextField("Shares", text: $editQuantity)
                .focused($editFocused)
                .frame(width: Width.shares - 6)
            TextField("Avg price", text: $editPrice, prompt: Text("Avg price"))
                .frame(width: Width.average - 30)
            Button { commitEdit(h) } label: { Image(systemName: "checkmark") }
                .buttonStyle(.borderless)
                .disabled((parseNumber(editQuantity) ?? 0) <= 0)
        }
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .onSubmit { commitEdit(h) }
        .onExitCommand { editing = nil }
        .frame(width: Width.shares + Width.average + 10, alignment: .trailing)
    }

    private func startEdit(_ h: Holding) {
        pendingDelete = nil
        editQuantity = h.quantity.editableQuantity
        editPrice = h.averagePrice.map { $0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(Locale(identifier: "pt_BR"))) } ?? ""
        editing = h.ticker
        editFocused = true
    }

    /// An empty price field clears the average price.
    private func commitEdit(_ h: Holding) {
        guard let q = parseNumber(editQuantity), q > 0 else { return }
        store.setQuantity(h.ticker, to: q, averagePrice: parseNumber(editPrice).flatMap { $0 > 0 ? $0 : nil })
        editing = nil
    }
}
