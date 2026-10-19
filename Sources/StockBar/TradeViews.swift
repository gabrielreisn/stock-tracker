import SwiftUI

struct AddTradeView: View {
    @Environment(PortfolioStore.self) private var store
    @Binding var screen: Screen

    @State private var ticker = ""
    @State private var kind: TradeKind = .buy
    @State private var date = Date.now
    @State private var quantity = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var tickerFocused: Bool

    private var normalizedTicker: String {
        ticker.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var trade: Trade? {
        guard !normalizedTicker.isEmpty, let q = parseNumber(quantity), q > 0 else { return nil }
        return Trade(ticker: normalizedTicker, kind: kind, date: date, quantity: q)
    }

    private var held: Double {
        store.holdings.first { $0.ticker == normalizedTicker }?.quantity ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Add trade", screen: $screen)
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(TradeKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Ticker", text: $ticker, prompt: Text("PETR4"))
                    .focused($tickerFocused)
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("Quantity", text: $quantity, prompt: Text("100"))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 190)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            } else if kind == .sell, let q = parseNumber(quantity), q > held {
                Label("You hold \(held.quantity) \(normalizedTicker)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { screen = .overview }.keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trade == nil || checking)
            }
            .padding(14)
        }
        .onAppear { tickerFocused = true }
        .onChange(of: ticker) { error = nil }
        .onChange(of: date) { error = nil }
    }

    /// Makes sure the ticker exists on B3 before saving.
    private func submit() {
        guard let trade else { return }
        checking = true
        Task {
            defer { checking = false }
            guard (try? await MarketData.intraday(for: trade.ticker)) != nil else {
                error = "Couldn't find \(trade.ticker) on B3"
                return
            }
            store.add(trade)
            screen = .overview
        }
    }
}

struct TradesView: View {
    @Environment(PortfolioStore.self) private var store
    @Binding var screen: Screen
    @State private var pendingDelete: Trade.ID?
    @State private var editing: Trade.ID?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Trades", screen: $screen)
            Divider()
            if store.trades.isEmpty {
                Text("No trades yet").foregroundStyle(.secondary).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.trades.reversed()) { trade in
                            row(trade)
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private func row(_ trade: Trade) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trade.ticker).font(.callout.weight(.semibold))
                Text((trade.kind == .sell ? "Sold · " : "") + trade.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if editing == trade.id {
                TextField("Quantity", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($editFocused)
                    .onSubmit { commitEdit(trade) }
                    .onExitCommand { editing = nil }
                Button { commitEdit(trade) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.borderless)
                    .disabled((parseNumber(editText) ?? 0) <= 0)
                    .help("Save")
            } else {
                Button { startEdit(trade) } label: {
                    Text("\(trade.quantity.quantity) shares").font(.callout.monospacedDigit())
                }
                .buttonStyle(.plain)
                .help("Click to edit the quantity")
                Button { startEdit(trade) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Edit quantity")
                if pendingDelete == trade.id {
                    Button("Delete") { store.delete(trade); pendingDelete = nil }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                } else {
                    Button { pendingDelete = trade.id } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Delete")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private func startEdit(_ trade: Trade) {
        pendingDelete = nil
        editText = trade.quantity.editableQuantity
        editing = trade.id
        editFocused = true
    }

    private func commitEdit(_ trade: Trade) {
        guard let quantity = parseNumber(editText), quantity > 0 else { return }
        var updated = trade
        updated.quantity = quantity
        store.update(updated)
        editing = nil
    }
}

