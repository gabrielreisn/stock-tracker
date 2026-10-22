import Charts
import SwiftUI

/// A fund's fact sheet: CVM registry facts and figures from the daily reports for every fund,
/// plus fees, terms, strategy and portfolio when the fund has filed a lâmina.
struct FundDetailView: View {
    @Environment(FundStore.self) private var funds
    @Environment(\.dismiss) private var dismiss
    let compared: ComparedFund

    @State private var details: FundDetails?
    @State private var lamina: Lamina?
    @State private var loadingLamina = true

    private var fund: FundInfo { compared.fund }
    private static let brazil = Locale(identifier: "pt_BR")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    keyFigures
                    performance
                    sizeAndFlows
                    feesAndTerms
                    if let lamina { strategy(lamina) }
                    if let lamina, !lamina.portfolio.isEmpty { portfolio(lamina) }
                    if let lamina, !lamina.yearly.isEmpty { officialReturns(lamina) }
                    registration
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 780)
        .task {
            details = await funds.details(for: fund.id)
            lamina = await CVM.lamina(for: fund)
            loadingLamina = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lamina?.text("NM_FANTASIA") ?? fund.name)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if lamina?.text("NM_FANTASIA") != nil {
                    Text(fund.name).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Text(fund.formattedCNPJ).monospacedDigit().textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fund.formattedCNPJ, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy CNPJ")
                    if let manager = fund.manager { Text("· \(manager)").lineLimit(1) }
                }
                .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let category = fund.category { Badge(text: category) }
                    if let risk = lamina?.number("CLASSE_RISCO_ADMIN") { Badge(text: "Risk \(Int(risk)) of 5", tint: riskColor(Int(risk))) }
                    if details?.longTermTax == true { Badge(text: "Long-term tax") }
                    if details?.exclusive == true { Badge(text: "Exclusive", tint: .orange) }
                }
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    // MARK: - Key figures

    private var keyFigures: some View {
        let stats = funds.stats[fund.id]
        let latest = funds.summaries[fund.id]?.last?.summary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            Tile(title: "Return (\(funds.range.rawValue))", value: stats?.totalReturn.signedPercent ?? "—", tint: stats.map { $0.totalReturn.gainColor })
            Tile(title: "% of CDI", value: stats?.percentOfCDI.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
            Tile(title: "Volatility (yearly)", value: stats?.volatility.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
            Tile(title: "Max drawdown", value: stats.map { $0.maxDrawdown < -0.00005 ? $0.maxDrawdown.formatted(.percent.precision(.fractionLength(1))) : "—" } ?? "—",
                 tint: (stats?.maxDrawdown ?? 0) < -0.00005 ? .red : nil)
            Tile(title: "Net assets", value: (latest?.netAssets ?? fund.netAssets).map(\.compactReais) ?? "—")
            Tile(title: "Shareholders", value: latest.map { $0.shareholders.formatted(.number.locale(Self.brazil)) } ?? "—")
        }
    }

    // MARK: - Performance

    private var performance: some View {
        let years = funds.monthlyReturns(fund.id)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return SheetSection(title: "Monthly returns", note: "Over the \(funds.range.rawValue) range loaded in the comparison. Change the range to see more years.") {
            if years.isEmpty {
                Text("No share prices loaded yet.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 5) {
                    GridRow {
                        Text("")
                        ForEach(months, id: \.self) { Text($0) }
                        Text("Year").fontWeight(.semibold)
                        Text("CDI")
                        Text("% CDI")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    ForEach(years) { y in
                        GridRow {
                            Text(String(y.year)).fontWeight(.semibold).gridColumnAlignment(.leading)
                            ForEach(1...12, id: \.self) { m in
                                Text(y.months[m].map { $0.formatted(.number.precision(.fractionLength(2)).locale(Self.brazil)) } ?? "")
                                    .foregroundStyle((y.months[m] ?? 0).gainColor)
                            }
                            Text(y.total.map { $0.formatted(.percent.precision(.fractionLength(2)).locale(Self.brazil)) } ?? "—")
                                .fontWeight(.semibold).foregroundStyle((y.total ?? 0).gainColor)
                            Text(y.cdi.map { $0.formatted(.percent.precision(.fractionLength(2)).locale(Self.brazil)) } ?? "—")
                                .foregroundStyle(.secondary)
                            Text(percentOfCDI(y.total, y.cdi)).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                Text("Monthly figures in %.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func percentOfCDI(_ value: Double?, _ cdi: Double?) -> String {
        guard let value, let cdi, cdi > 0.0001 else { return "—" }
        return (value / cdi).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Size and flows

    private var sizeAndFlows: some View {
        let rows = funds.summaries[fund.id] ?? []
        return SheetSection(title: "Net assets and flows", note: "Month-end net assets and each month's subscriptions minus redemptions, from CVM's daily reports.") {
            if rows.count < 2 {
                Text("Not enough months loaded yet.").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    Chart(rows, id: \.month) { r in
                        AreaMark(x: .value("Month", DayKey.date(r.month * 100 + 15)), y: .value("Net assets", r.summary.netAssets))
                            .foregroundStyle(.blue.opacity(0.18))
                        LineMark(x: .value("Month", DayKey.date(r.month * 100 + 15)), y: .value("Net assets", r.summary.netAssets))
                            .foregroundStyle(.blue)
                    }
                    .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.compactReais) } } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
                    .frame(height: 150)
                    Chart(rows, id: \.month) { r in
                        let net = r.summary.inflow - r.summary.outflow
                        BarMark(x: .value("Month", DayKey.date(r.month * 100 + 15), unit: .month), y: .value("Net flow", net))
                            .foregroundStyle(net >= 0 ? Color.green : Color.red)
                    }
                    .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(d.compactReais) } } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
                    .frame(height: 150)
                }
                HStack {
                    Text("Net assets").frame(maxWidth: .infinity)
                    Text("Net flows (subscriptions − redemptions)").frame(maxWidth: .infinity)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Fees and terms (lâmina)

    @ViewBuilder
    private var feesAndTerms: some View {
        SheetSection(title: "Fees and terms", note: lamina.map { "From the fund's lâmina filed for \(DayKey.date($0.date).formatted(.dateTime.month(.wide).year()))." }) {
            if let l = lamina {
                facts([
                    ("Management fee", managementFee(l)),
                    ("Performance fee", l.text("TAXA_PERFM").flatMap { $0.lowercased().hasPrefix("não") ? "None" : $0 } ?? "None"),
                    ("Total expense ratio (12m)", l.number("PR_PL_DESPESA").map(percent)),
                    ("Entry fee", fee(l.number("TAXA_ENTR"), l.text("CONDIC_ENTR"))),
                    ("Exit fee", fee(l.number("TAXA_SAIDA"), l.text("CONDIC_SAIDA"))),
                    ("Minimum initial investment", l.number("INVEST_INICIAL_MIN").map(reais)),
                    ("Minimum additional investment", l.number("INVEST_ADIC").map(reais)),
                    ("Minimum redemption", l.number("RESGATE_MIN").map(reais)),
                    ("Minimum balance", l.number("VL_MIN_PERMAN").map(reais)),
                    ("Order cut-off", l.text("HORA_APLIC_RESGATE")),
                    ("Subscription price", conversion(l.number("QT_DIA_CONVERSAO_COTA_COMPRA"), l.text("CONVERSAO_COTA_COMPRA"))),
                    ("Redemption price", conversion(l.number("QT_DIA_CONVERSAO_COTA_RESGATE"), l.text("CONVERSAO_COTA_CANC"))),
                    ("Redemption paid", payment(l.number("QT_DIA_PAGTO_RESGATE"), l.text("TP_DIA_PAGTO_RESGATE"))),
                    ("Lock-up", l.number("QT_DIA_CAREN").flatMap { $0 > 0 ? "\(Int($0)) days" : nil } ?? l.text("CONDIC_CAREN")),
                ])
            } else if loadingLamina {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking for the fund's lâmina…").foregroundStyle(.secondary) }
            } else {
                Label {
                    Text("This fund hasn't filed a lâmina with CVM in the last 12 months, so its fees, minimums and redemption terms aren't in CVM's open data. Since CVM Resolution 175, only some funds file one; check the manager's website or your broker.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: "info.circle") }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func managementFee(_ l: Lamina) -> String? {
        if let fee = l.number("TAXA_ADM") { return percent(fee) + " a year" }
        if let lo = l.number("TAXA_ADM_MIN"), let hi = l.number("TAXA_ADM_MAX") {
            return lo == hi ? percent(lo) + " a year" : "\(percent(lo)) to \(percent(hi)) a year"
        }
        return l.text("TAXA_ADM_OBS")
    }

    private func fee(_ value: Double?, _ condition: String?) -> String {
        guard let value, value > 0 else { return "None" }
        return percent(value) + (condition.map { " (\($0))" } ?? "")
    }

    private func conversion(_ days: Double?, _ basis: String?) -> String? {
        guard let days else { return basis }
        return "D+\(Int(days))" + (basis.map { ", \($0.lowercased())" } ?? "")
    }

    private func payment(_ days: Double?, _ kind: String?) -> String? {
        guard let days else { return nil }
        return "D+\(Int(days))" + (kind.map { " (\($0.lowercased()))" } ?? "")
    }

    // MARK: - Strategy, portfolio, official returns (lâmina)

    private func strategy(_ l: Lamina) -> some View {
        SheetSection(title: "Strategy") {
            VStack(alignment: .leading, spacing: 12) {
                if let objective = l.text("OBJETIVO") { paragraph("Objective", objective) }
                if let policy = l.text("POLIT_INVEST") { paragraph("Investment policy", policy) }
                if let audience = l.text("PUBLICO_ALVO") { paragraph("Target investors", audience) }
                if let restrictions = l.text("RESTR_INVEST"), !restrictions.lowercased().hasPrefix("não") { paragraph("Restrictions", restrictions) }
                facts([
                    ("Max. abroad", l.number("PR_PL_ATIVO_EXTERIOR").map(percent)),
                    ("Max. private credit", l.number("PR_PL_ATIVO_CRED_PRIV").map(percent)),
                    ("Max. leverage", l.number("PR_PL_ALAVANC").map(percent)),
                    ("Max. in a single issuer", l.number("PR_ATIVO_EMISSOR").map(percent)),
                    ("Can lose more than invested", l.text("RISCO_PERDA_NEGATIVO").map { $0 == "S" ? "Yes" : "No" }),
                ])
            }
        }
    }

    private func portfolio(_ l: Lamina) -> some View {
        let maxPercent = l.portfolio.map(\.percent).max() ?? 100
        return SheetSection(title: "Portfolio mix", note: "Share of net assets by asset type, as of the lâmina.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(l.portfolio.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Text(item.asset).lineLimit(1).frame(width: 300, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2).fill(.blue.opacity(0.7))
                                .frame(width: max(2, geo.size.width * max(0, item.percent) / max(maxPercent, 1)))
                        }
                        .frame(height: 10)
                        Text(percent(item.percent)).monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func officialReturns(_ l: Lamina) -> some View {
        let index = l.text("INDICE_REFER") ?? "Benchmark"
        return SheetSection(title: "Yearly returns (lâmina)", note: "As reported by the fund, against its own benchmark.") {
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 5) {
                GridRow {
                    Text("Year").gridColumnAlignment(.leading)
                    Text("Fund")
                    Text(index)
                    Text("% of \(index)")
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(l.yearly, id: \.year) { y in
                    GridRow {
                        Text(String(y.year))
                        Text(y.fund.map { percent($0) } ?? "—").foregroundStyle((y.fund ?? 0).gainColor)
                        Text(y.index.map { percent($0) } ?? "—").foregroundStyle(.secondary)
                        Text(percentOfCDI(y.fund, y.index)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout.monospacedDigit())
        }
    }

    // MARK: - Registration

    private var registration: some View {
        SheetSection(title: "Registration", note: "From CVM's fund registry.") {
            facts([
                ("Started", details?.inception.flatMap(formatDate)),
                ("CVM class", details?.cvmClass),
                ("ANBIMA category", fund.category),
                ("Benchmark", details?.benchmark),
                ("Structure", details?.condominium.map { $0 == "Aberto" ? "Open-ended" : $0 == "Fechado" ? "Closed-ended" : $0 }),
                ("Target investors", details?.audience),
                ("Long-term tax treatment", yesNo(details?.longTermTax)),
                ("ESG", yesNo(details?.esg)),
                ("Can invest 100% abroad", yesNo(details?.fullyAbroad)),
                ("Fund CNPJ", details?.fundCNPJ.flatMap { $0 == fund.cnpj ? nil : CVM.formatCNPJ($0) }),
                ("Sub-class", fund.subclass),
                ("Manager", fund.manager),
                ("Administrator", details?.administrator),
                ("Custodian", details?.custodian),
                ("Controller", details?.controller),
                ("Auditor", details?.auditor),
                ("Website", lamina?.text("ENDER_ELETRONICO")),
                ("Customer service", lamina?.text("TEL_SAC")),
            ])
        }
    }

    // MARK: - Building blocks

    /// Two-column label/value list; rows without a value are left out.
    private func facts(_ rows: [(String, String?)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            ForEach(rows.filter { $0.1 != nil }, id: \.0) { label, value in
                GridRow(alignment: .firstTextBaseline) {
                    Text(label).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                    Text(value!).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
    }

    private func paragraph(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Self.brazil)) + "%"
    }

    private func reais(_ value: Double) -> String {
        value.formatted(.currency(code: "BRL").precision(.fractionLength(0...2)).locale(Self.brazil))
    }

    private func yesNo(_ value: Bool?) -> String? { value.map { $0 ? "Yes" : "No" } }

    private func formatDate(_ iso: String) -> String? {
        Int(iso.replacingOccurrences(of: "-", with: "")).map { DayKey.date($0).formatted(date: .long, time: .omitted) }
    }

    private func riskColor(_ level: Int) -> Color {
        switch level {
        case ...2: .green
        case 3: .yellow
        default: .red
        }
    }
}

private struct SheetSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tile: View {
    let title: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
    }
}
