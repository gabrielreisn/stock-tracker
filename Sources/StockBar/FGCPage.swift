import SwiftUI

/// Banco Central's prudential conglomerates (IF.data), which is how the FGC applies its per-institution limit:
/// every institution in one conglomerate shares the same R$ 250 mil.
struct Conglomerate: Codable, Hashable {
    var code: String
    var name: String
    /// Institutions in it, by name.
    var members: [String]
}

enum BCBConglomerates {
    private static var cacheURL: URL { CVM.cacheDirectory.appendingPathComponent("bcb-conglomerates.json") }

    /// CNPJ root (8 digits) → conglomerate, from the latest quarter IF.data has published. Cached for 30 days.
    static func load() async -> [String: Conglomerate] {
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode([String: Conglomerate].self, from: $0) }
        if let cached, let date = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date,
           Date.now.timeIntervalSince(date) < 30 * 86_400 { return cached }

        struct Response: Decodable {
            struct Row: Decodable { var CodInst: String; var NomeInstituicao: String?; var CodConglomeradoPrudencial: String? }
            var value: [Row]
        }
        // The last few quarter ends, fetched side by side (an unpublished quarter can hang): use the newest with data.
        var quarters: [Int] = [], month = DayKey.from(.now) / 100
        while quarters.count < 3 {
            month = DayKey.addMonths(month * 100 + 1, -1) / 100
            if month % 100 % 3 == 0 { quarters.append(month) }
        }
        let responses = await withTaskGroup(of: (Int, [Response.Row]?).self) { group in
            for q in quarters {
                group.addTask {
                    let address = "https://olinda.bcb.gov.br/olinda/servico/IFDATA/versao/v1/odata/IfDataCadastro(AnoMes=@AnoMes)?@AnoMes=\(q)&$select=CodInst,NomeInstituicao,CodConglomeradoPrudencial&$format=json"
                    var request = URLRequest(url: URL(string: address)!)
                    request.timeoutInterval = 45
                    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return (q, nil) }
                    return (q, (try? JSONDecoder().decode(Response.self, from: data))?.value)
                }
            }
            return await group.reduce(into: [Int: [Response.Row]]()) { $0[$1.0] = $1.1 }
        }
        if let rows = quarters.lazy.compactMap({ responses[$0] }).first(where: { !$0.isEmpty }) {
            // Rows coded "C…" are the conglomerates themselves; the rest are institutions, coded by CNPJ root.
            let names = Dictionary(rows.map { ($0.CodInst, $0.NomeInstituicao ?? $0.CodInst) }, uniquingKeysWith: { a, _ in a })
            let institutions = rows.filter { !$0.CodInst.hasPrefix("C") }
            let members = Dictionary(grouping: institutions.filter { $0.CodConglomeradoPrudencial != nil }) { $0.CodConglomeradoPrudencial! }
            var result: [String: Conglomerate] = [:]
            for row in institutions {
                guard let code = row.CodConglomeradoPrudencial else { continue }
                let name = (names[code] ?? code).replacingOccurrences(of: " - PRUDENCIAL", with: "")
                result[row.CodInst] = Conglomerate(code: code, name: name, members: (members[code] ?? []).compactMap(\.NomeInstituicao).sorted())
            }
            try? JSONEncoder().encode(result).write(to: cacheURL, options: .atomic)
            return result
        }
        return cached ?? [:]
    }
}

/// Exposure per institution against the FGC guarantee: R$ 250 mil per CPF per institution (or conglomerate),
/// R$ 1 milhão per CPF overall every four years. Only CDB, LC, LCI and LCA count; CRI, CRA and debentures aren't covered.
struct FGCPage: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(PluggyStore.self) private var pluggy
    @State private var editing: Bond?
    @State private var conglomerates: [String: Conglomerate] = [:]

    static let perInstitution = 250_000.0
    static let overall = 1_000_000.0

    struct Exposure: Identifiable {
        var key: String
        var names: [String]
        var cnpjs: [String]
        var bonds: [(bond: Bond, value: BondValuation)]
        var gross: Double { bonds.reduce(0) { $0 + $1.value.gross } }
        /// Gross value at each bond's maturity, estimated with today's rates.
        var atMaturity: Double { bonds.reduce(0) { $0 + ($1.value.atMaturity ?? $1.value.gross) } }
        var conglomerate: Conglomerate?
        var hasCNPJ: Bool { !cnpjs.isEmpty }
        var id: String { key }
    }

    /// The issuer's BCB conglomerate, else its CNPJ root (the legal entity), else its name when the CNPJ is unknown.
    private func key(for bond: Bond) -> String {
        guard let cnpj = bond.issuerCNPJ, cnpj.count == 14 else {
            return "name:" + bond.issuer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter)
        }
        let root = String(cnpj.prefix(8))
        return conglomerates[root]?.code ?? root
    }

    private var exposures: [Exposure] {
        let pricer = store.bondPricer
        var byKey: [String: Exposure] = [:]
        for bond in store.bonds where bond.kind.isFGCCovered && bond.maturityDay >= DayKey.from(.now) {
            let k = key(for: bond)
            var e = byKey[k] ?? Exposure(key: k, names: [], cnpjs: [], bonds: [],
                                         conglomerate: bond.issuerCNPJ.flatMap { conglomerates[String($0.prefix(8))] })
            e.bonds.append((bond, pricer.value(bond)))
            if !e.names.contains(bond.issuer) { e.names.append(bond.issuer) }
            if let c = bond.issuerCNPJ, !e.cnpjs.contains(c) { e.cnpjs.append(c) }
            byKey[k] = e
        }
        return byKey.values.sorted { $0.gross > $1.gross }
    }

    var body: some View {
        let exposures = exposures
        let covered = exposures.reduce(0) { $0 + min($1.gross, Self.perInstitution) }
        let above = exposures.reduce(0) { $0 + max(0, $1.gross - Self.perInstitution) }
        let notCovered = store.bonds.filter { !$0.kind.isFGCCovered }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FGC Watcher").font(.title2.weight(.semibold))
                    Text("The FGC guarantees up to R$ 250 mil per CPF in each institution or financial conglomerate, and R$ 1 milhão per CPF in total every four years. It covers CDB, LC, LCI and LCA (and deposits), not CRI, CRA or debentures.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    tile("Guaranteed", covered.reais, detail: "across \(exposures.count) conglomerates")
                    tile("Above the limit", above > 0 ? above.reais : "None", tint: above > 0 ? .red : .green,
                         detail: above > 0 ? "not guaranteed" : "every conglomerate within R$ 250 mil")
                    tile("Overall limit used", (covered / Self.overall).percent, tint: covered > Self.overall * 0.9 ? .orange : nil,
                         detail: "of R$ 1 milhão per CPF")
                }
                .fixedSize(horizontal: false, vertical: true)
                legend
                if exposures.isEmpty {
                    Text("No CDB, LC, LCI or LCA in Bonds.").foregroundStyle(.secondary).padding(24)
                }
                ForEach(exposures) { institution($0) }
                if !notCovered.isEmpty { uncovered(notCovered) }
                Text("Values are gross (principal plus interest so far), which is what the guarantee is measured on. “At maturity” carries today's CDI and IPCA forward. Institutions are grouped by their prudential conglomerate in Banco Central's IF.data, so banks of the same group share one limit.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .sheet(item: $editing) { BondForm(bond: $0).environment(store) }
        .task { conglomerates = await BCBConglomerates.load() }
        .task(id: pluggy.lastSync) {
            // Issuer CNPJs come from Open Finance; sync once if it hasn't been this session.
            if pluggy.lastSync == nil, pluggy.isConfigured, !pluggy.itemIDs.isEmpty, store.bonds.contains(where: { $0.issuerCNPJ == nil }) {
                await pluggy.sync()
            } else {
                fillCNPJsFromOpenFinance()
            }
        }
    }

    // MARK: - Institution card

    private func institution(_ e: Exposure) -> some View {
        let share = e.gross / Self.perInstitution
        let tint: Color = share > 1 ? .red : share > 0.8 ? .orange : .green
        let pricer = store.bondPricer
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.names.joined(separator: " + ")).font(.headline)
                    if e.hasCNPJ {
                        Text(e.cnpjs.map(CVM.formatCNPJ).joined(separator: " · ")).font(.caption.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                        if let c = e.conglomerate {
                            let others = c.members.filter { m in !e.names.contains { fold($0) == fold(m) } }
                            Text("Conglomerate \(c.name)" + (others.isEmpty ? "" : " · shares the limit with \(others.joined(separator: ", "))"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } else {
                        Label("CNPJ unknown: edit the bonds or sync Open Finance", systemImage: "questionmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            // Exposure against the limit, with a tick where it's headed by maturity.
            GeometryReader { geo in
                let width = geo.size.width
                let scale = max(1.0, e.atMaturity / Self.perInstitution, share) * 1.05
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint.opacity(0.85)).frame(width: width * min(share / scale, 1))
                    Rectangle().fill(.primary.opacity(0.7)).frame(width: 2, height: 16)
                        .offset(x: width * (1 / scale) - 1)
                        .help("R$ 250 mil limit")
                    if e.atMaturity > e.gross {
                        Circle().strokeBorder(tint, lineWidth: 2).frame(width: 10, height: 10)
                            .offset(x: width * min(e.atMaturity / Self.perInstitution / scale, 1) - 5)
                            .help("Estimated at maturity: \(e.atMaturity.reais)")
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 18) {
                Text(e.gross.reais).fontWeight(.semibold)
                if share > 1 {
                    Text("\((e.gross - Self.perInstitution).reais) above the limit").foregroundStyle(.red)
                } else {
                    Text("\((Self.perInstitution - e.gross).reais) headroom").foregroundStyle(.secondary)
                }
                Spacer()
                Text("At maturity (est.) \(e.atMaturity.reais)")
                    .foregroundStyle(e.atMaturity > Self.perInstitution && share <= 1 ? .orange : .secondary)
                    .help(e.atMaturity > Self.perInstitution && share <= 1 ? "Interest will take this above R$ 250 mil before the bonds mature" : "")
            }
            .font(.callout.monospacedDigit())

            VStack(spacing: 4) {
                ForEach(e.bonds, id: \.bond.id) { item in
                    Button { editing = item.bond } label: {
                        HStack {
                            Text("\(item.bond.kind.rawValue) \(item.bond.code)").font(.caption.monospaced())
                            Text(item.bond.indexer.describe(item.bond.rate)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("matures \(DayKey.date(item.bond.maturityDay).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(pricer.value(item.bond).gross.reais).font(.caption.monospacedDigit()).frame(width: 110, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit bond")
                }
            }
        }
        .padding(16)
        .card()
    }

    private func uncovered(_ bonds: [Bond]) -> some View {
        let pricer = store.bondPricer
        return VStack(alignment: .leading, spacing: 6) {
            Text("Not covered by the FGC").font(.headline)
            ForEach(bonds) { b in
                HStack {
                    Text("\(b.kind.rawValue) · \(b.issuer)")
                    Spacer()
                    Text(pricer.value(b).gross.reais).monospacedDigit()
                }
                .font(.callout)
            }
        }
        .padding(16)
        .card()
    }

    private func tile(_ title: String, _ value: String, tint: Color? = nil, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? .primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Key for the bars on each card.
    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) { Capsule().fill(.green.opacity(0.85)).frame(width: 22, height: 8); Text("Value today") }
            HStack(spacing: 6) { Circle().strokeBorder(.green, lineWidth: 2).frame(width: 10, height: 10); Text("Estimated at maturity") }
            HStack(spacing: 6) { Rectangle().fill(.primary.opacity(0.7)).frame(width: 2, height: 14); Text("R$ 250 mil limit") }
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8); Text("under 80%")
                Circle().fill(.orange).frame(width: 8, height: 8); Text("80–100%")
                Circle().fill(.red).frame(width: 8, height: 8); Text("over the limit")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter)
    }

    // MARK: - CNPJs from Open Finance

    /// Bonds without an issuer CNPJ take it from the Open Finance position with the same code.
    private func fillCNPJsFromOpenFinance() {
        for bond in store.bonds where bond.issuerCNPJ == nil {
            let match = pluggy.investments.first { inv in
                guard inv.type == "FIXED_INCOME" else { return false }
                let code = (inv.code ?? "").uppercased().replacingOccurrences(of: "CDB-", with: "")
                return !code.isEmpty && (code == bond.code || code.hasSuffix(bond.code))
            }
            guard let digits = match?.issuerCNPJ?.filter(\.isNumber), digits.count == 14 else { continue }
            var updated = bond
            updated.issuerCNPJ = digits
            store.saveBond(updated)
        }
    }
}
