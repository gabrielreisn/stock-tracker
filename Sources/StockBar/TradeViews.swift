import SwiftUI

struct TradesView: View {
    @Environment(PortfolioStore.self) private var store
    @Binding var screen: Screen
    @State private var pendingDelete: Trade.ID?
    @State private var editing: Trade.ID?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    @State private var ticker = ""
    @State private var quantity = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var tickerFocused: Bool

    private var normalizedTicker: String {
        ticker.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// New trades are buys dated today: only the quantities held matter for the numbers.
    private var trade: Trade? {
        guard !normalizedTicker.isEmpty, let q = parseNumber(quantity), q > 0 else { return nil }
        return Trade(ticker: normalizedTicker, kind: .buy, date: .now, quantity: q)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Trades", screen: $screen)
            form
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
        .onAppear { tickerFocused = true }
        .onChange(of: ticker) { error = nil }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ticker", text: $ticker, prompt: Text("PETR4"))
                    .focused($tickerFocused)
                TextField("Quantity", text: $quantity, prompt: Text("100"))
                    .frame(width: 90)
                    .onSubmit(submit)
                Button {
                    submit()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trade == nil || checking)
            }
            .textFieldStyle(.roundedBorder)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// Makes sure the ticker exists before saving.
    private func submit() {
        guard let trade, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            guard (try? await MarketData.intraday(for: trade.ticker)) != nil else {
                error = "Couldn't find \(trade.ticker)"
                return
            }
            store.add(trade)
            ticker = ""
            quantity = ""
            tickerFocused = true
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

