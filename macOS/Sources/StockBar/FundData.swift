import Foundation

/// A fund class (or one of its sub-classes) from CVM's registry. Only FIF classes are listed:
/// they're the ones that report daily share prices.
struct FundInfo: Codable, Identifiable, Hashable, Sendable {
    /// CNPJ digits, plus "|<sub-class id>" for a sub-class (each sub-class has its own share price).
    var id: String
    var cnpj: String
    var name: String
    var manager: String?
    var category: String?
    var netAssets: Double?

    var formattedCNPJ: String { CVM.formatCNPJ(cnpj) }
    var subclass: String? { id.split(separator: "|").dropFirst().first.map(String.init) }
}

/// Registry facts for the fact sheet, kept apart from the search index so search stays light.
struct FundDetails: Codable, Sendable {
    var fundCNPJ: String?
    /// The parent fund's constitution date (a class's own start date is just its 2025 adaptation).
    var inception: String?
    var cvmClass: String?
    var benchmark: String?
    var audience: String?
    var condominium: String?
    var exclusive: Bool?
    var longTermTax: Bool?
    var esg: Bool?
    var fullyAbroad: Bool?
    var administrator: String?
    var custodian: String?
    var auditor: String?
    var controller: String?
}

/// End-of-month figures from the daily reports.
struct MonthSummary: Sendable {
    var netAssets: Double
    var shareholders: Int
    var inflow: Double
    var outflow: Double
}

struct MonthData: Sendable {
    var quotas: [String: [(day: Int, quota: Double)]] = [:]
    var summaries: [String: MonthSummary] = [:]
}

/// The fund's own fact sheet ("lâmina"), as filed to CVM. Only some funds file one.
struct Lamina: Sendable {
    var date: Int
    var fields: [String: String]
    var portfolio: [(asset: String, percent: Double)]
    var yearly: [(year: Int, fund: Double?, index: Double?)]

    func text(_ key: String) -> String? {
        guard let v = fields[key]?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v != "-" else { return nil }
        return v
    }

    func number(_ key: String) -> Double? { text(key).flatMap(Double.init) }
}

/// CVM open data (dados.cvm.gov.br): the fund registry, daily reports ("informe diário") and fact sheets ("lâmina").
enum CVM {
    /// Monthly report files start here; older years only come as yearly archives.
    static let firstMonth = 202101
    private static let base = "https://dados.cvm.gov.br/dados/FI"

    static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StockBar/CVM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Caches from before columns were read by name (pre-Dec 2023 months were misread).
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.hasPrefix("quotas-") || name == "funds.json" {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        return dir
    }()

    static func formatCNPJ(_ digits: String) -> String {
        guard digits.count == 14 else { return digits }
        let c = Array(digits)
        return "\(String(c[0..<2])).\(String(c[2..<5])).\(String(c[5..<8]))/\(String(c[8..<12]))-\(String(c[12..<14]))"
    }

    // MARK: - Registry

    private static var indexURL: URL { cacheDirectory.appendingPathComponent("funds-v2.json") }
    private static var detailsURL: URL { cacheDirectory.appendingPathComponent("fund-details-v2.json") }
    /// Operating classes that aren't FIFs (FIDC, FIP, FII…): no daily prices, so not in the search index,
    /// but still worth knowing by CNPJ for autofill.
    private static var othersURL: URL { cacheDirectory.appendingPathComponent("fund-registry-others-v1.json") }

    /// A fund class as the registry has it, for filling in a holding from its CNPJ.
    struct RegisteredFund: Codable, Sendable {
        var name: String
        /// The CVM type at the end of "Classes de Cotas de Fundos …": FIF, FIDC, FIP, FII…
        var type: String
    }

    /// Every operating FIF class and sub-class. Cached for a week; a stale copy is used if CVM is unreachable.
    static func fundIndex() async throws -> [FundInfo] {
        let cached = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([FundInfo].self, from: $0) }
        if let cached, let age = age(of: indexURL), age < 7 * 86_400, FileManager.default.fileExists(atPath: detailsURL.path),
           FileManager.default.fileExists(atPath: othersURL.path) {
            return cached
        }
        do {
            guard let zip = try await download("\(base)/CAD/DADOS/registro_fundo_classe.zip") else {
                throw MarketDataError.badResponse("the CVM fund registry")
            }
            defer { try? FileManager.default.removeItem(at: zip) }
            let (funds, details, others) = try await Task.detached(priority: .userInitiated) { try parseRegistry(zip) }.value
            try? JSONEncoder().encode(details).write(to: detailsURL, options: .atomic)
            try? JSONEncoder().encode(others).write(to: othersURL, options: .atomic)
            try? JSONEncoder().encode(funds).write(to: indexURL, options: .atomic)
            return funds
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    /// Registry details for every fund in the index, keyed like `FundInfo.id`.
    static func fundDetails() async -> [String: FundDetails] {
        await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: detailsURL)).flatMap { try? JSONDecoder().decode([String: FundDetails].self, from: $0) } ?? [:]
        }.value
    }

    private static func parseRegistry(_ zip: URL) throws -> ([FundInfo], [String: FundDetails], [String: RegisteredFund]) {
        let funds = Table(try unzip(zip, entry: "registro_fundo.csv"))
        let classes = Table(try unzip(zip, entry: "registro_classe.csv"))
        let subclasses = Table(try unzip(zip, entry: "registro_subclasse.csv"))
        let operating = "Em Funcionamento Normal"
        func flag(_ value: String?) -> Bool? { value.map { $0.trimmingCharacters(in: .whitespaces) == "S" } }

        var parents: [String: [Substring]] = [:]
        for row in funds.rows {
            if let id = funds.value(row, "ID_Registro_Fundo") { parents[id] = row }
        }

        var subclassesByClass: [String: [[Substring]]] = [:]
        for row in subclasses.rows where subclasses.value(row, "Situacao") == operating {
            if let classID = subclasses.value(row, "ID_Registro_Classe") { subclassesByClass[classID, default: []].append(row) }
        }

        var index: [FundInfo] = []
        var details: [String: FundDetails] = [:]
        var others: [String: RegisteredFund] = [:]
        for row in classes.rows {
            if classes.value(row, "Situacao") == operating, let type = classes.value(row, "Tipo_Classe"),
               !type.hasPrefix("Classes de Cotas de Fundos FIF"),
               let cnpj = classes.value(row, "CNPJ_Classe"), let name = classes.value(row, "Denominacao_Social") {
                let short = type.replacingOccurrences(of: "Classes de Cotas de Fundos ", with: "")
                others[cnpj] = RegisteredFund(name: name, type: short.split(separator: " ").first.map(String.init) ?? short)
            }
            guard classes.value(row, "Situacao") == operating,
                  classes.value(row, "Tipo_Classe")?.hasPrefix("Classes de Cotas de Fundos FIF") == true,
                  let cnpj = classes.value(row, "CNPJ_Classe"), let name = classes.value(row, "Denominacao_Social")
            else { continue }
            let parent = classes.value(row, "ID_Registro_Fundo").flatMap { parents[$0] }
            let fund = FundInfo(
                id: cnpj, cnpj: cnpj, name: name,
                manager: parent.flatMap { funds.value($0, "Gestor") },
                category: classes.value(row, "Classificacao_Anbima") ?? classes.value(row, "Classificacao"),
                netAssets: classes.value(row, "Patrimonio_Liquido").flatMap(Double.init)
            )
            let detail = FundDetails(
                fundCNPJ: parent.flatMap { funds.value($0, "CNPJ_Fundo") },
                inception: parent.flatMap { funds.value($0, "Data_Constituicao") ?? funds.value($0, "Data_Registro") }
                    ?? classes.value(row, "Data_Inicio"),
                cvmClass: classes.value(row, "Classificacao"),
                benchmark: classes.value(row, "Indicador_Desempenho"),
                audience: classes.value(row, "Publico_Alvo"),
                condominium: classes.value(row, "Forma_Condominio"),
                exclusive: flag(classes.value(row, "Exclusivo")),
                longTermTax: flag(classes.value(row, "Tributacao_Longo_Prazo")),
                esg: flag(classes.value(row, "Classe_ESG")),
                fullyAbroad: flag(classes.value(row, "Permitido_Aplicacao_CemPorCento_Exterior")),
                administrator: parent.flatMap { funds.value($0, "Administrador") },
                custodian: classes.value(row, "Custodiante"),
                auditor: classes.value(row, "Auditor"),
                controller: classes.value(row, "Controlador")
            )
            // A class split into sub-classes only reports prices per sub-class.
            if let subs = classes.value(row, "ID_Registro_Classe").flatMap({ subclassesByClass[$0] }) {
                for sub in subs {
                    guard let subID = subclasses.value(sub, "ID_Subclasse") else { continue }
                    var entry = fund
                    entry.id = "\(cnpj)|\(subID)"
                    entry.name = "\(name) — \(subclasses.value(sub, "Denominacao_Social") ?? subID)"
                    entry.netAssets = nil
                    var subDetail = detail
                    subDetail.audience = subclasses.value(sub, "Publico_Alvo") ?? detail.audience
                    subDetail.condominium = subclasses.value(sub, "Forma_Condominio") ?? detail.condominium
                    subDetail.exclusive = flag(subclasses.value(sub, "Exclusivo")) ?? detail.exclusive
                    index.append(entry)
                    details[entry.id] = subDetail
                }
            } else {
                index.append(fund)
                details[fund.id] = detail
            }
        }
        return (index, details, others)
    }

    /// A semicolon-separated CVM file (Windows-1252), addressed by column name.
    private struct Table {
        var columns: [String: Int] = [:]
        var rows: [[Substring]] = []

        init(_ data: Data) {
            var text = String(data: data, encoding: .windowsCP1252) ?? ""
            // Decoding hands back a bridged NSString, which Swift walks one UTF-16 unit at a time: re-encode as native UTF-8 first.
            text.makeContiguousUTF8()
            var lines = text.split(whereSeparator: \.isNewline)[...]
            guard let header = lines.popFirst() else { return }
            for (i, name) in header.split(separator: ";", omittingEmptySubsequences: false).enumerated() {
                columns[String(name)] = i
            }
            rows = lines.map { $0.split(separator: ";", omittingEmptySubsequences: false) }
        }

        func value(_ row: [Substring], _ column: String) -> String? {
            guard let i = columns[column], i < row.count, !row[i].isEmpty else { return nil }
            return String(row[i])
        }
    }

    // MARK: - Lookup by CNPJ

    /// What the registry says about a fund class, from the search index (FIFs) or the other classes.
    static func registeredFund(cnpj: String) async -> RegisteredFund? {
        let index = (try? await fundIndex()) ?? []
        if let f = index.first(where: { $0.id == cnpj }) ?? index.first(where: { $0.cnpj == cnpj }) {
            // Sub-class entries carry " — <sub-class>" after the class name.
            let name = f.id == cnpj ? f.name : (f.name.components(separatedBy: " — ").first ?? f.name)
            return RegisteredFund(name: name, type: "FIF")
        }
        let others = (try? Data(contentsOf: othersURL)).flatMap { try? JSONDecoder().decode([String: RegisteredFund].self, from: $0) }
        return others?[cnpj]
    }

    /// The newest share price CVM has for a fund: the daily report for FIFs, the monthly report for FIDCs
    /// (looking back a few months); nil for types that report neither.
    static func latestQuota(cnpj: String, type: String) async -> (day: Int, quota: Double)? {
        let current = DayKey.from(.now) / 100
        let months = (0..<4).map { DayKey.addMonths(current * 100 + 1, -$0) / 100 }
        for month in months {
            switch type {
            case "FIF":
                if let last = (try? await self.month(month, for: [cnpj]))?.quotas[cnpj]?.max(by: { $0.day < $1.day }) { return last }
            case "FIDC":
                if let last = await fidcQuotas(month: month, for: [cnpj])[cnpj] { return last }
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - Daily reports

    /// One month (yyyymm) of daily share prices and end-of-month figures for the given funds.
    /// Each month's report is boiled down to a small cache file; the last three months are refreshed
    /// twice a day because funds keep correcting them.
    static func month(_ month: Int, for ids: Set<String>) async throws -> MonthData {
        let url = cacheDirectory.appendingPathComponent("month-v2-\(month).bin")
        let stale = age(of: url).map { isRecent(month) && $0 > 12 * 3600 } ?? true
        if stale {
            do {
                if let zip = try await download("\(base)/DOC/INF_DIARIO/DADOS/inf_diario_fi_\(month).zip") {
                    defer { try? FileManager.default.removeItem(at: zip) }
                    let compact = try await Task.detached(priority: .userInitiated) { try compactMonth(unzip(zip)) }.value
                    try compact.write(to: url, options: .atomic)
                } else if !FileManager.default.fileExists(atPath: url.path) {
                    return MonthData()  // Not published yet (the first days of a month).
                }
            } catch {
                guard FileManager.default.fileExists(atPath: url.path) else { throw error }
            }
        }
        return readCompact(try Data(contentsOf: url), month: month, ids: ids)
    }

    private static func isRecent(_ month: Int) -> Bool {
        month >= DayKey.from(Calendar.current.date(byAdding: .month, value: -2, to: .now)!) / 100
    }

    /// The month's CSV as, per fund: [key length, key, row count, rows of (day, quota),
    /// last net assets, last shareholder count, month's inflows, month's outflows].
    /// Columns are found by name: files before Dec 2023 have CNPJ_FUNDO and no ID_SUBCLASSE.
    private static func compactMonth(_ csv: Data) throws -> Data {
        var out = Data()
        var key: [UInt8] = [], rows: [(UInt8, Double)] = []
        var summary = (lastDay: UInt8(0), netAssets: 0.0, shareholders: UInt32(0), inflow: 0.0, outflow: 0.0)
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { out.append(contentsOf: $0) } }
        func flush() {
            if !key.isEmpty, !rows.isEmpty {
                out.append(UInt8(key.count))
                out.append(contentsOf: key)
                let kept = rows.suffix(255)
                out.append(UInt8(kept.count))
                for (day, quota) in kept {
                    out.append(day)
                    append(quota.bitPattern.littleEndian)
                }
                append(summary.netAssets.bitPattern.littleEndian)
                append(summary.shareholders.littleEndian)
                append(summary.inflow.bitPattern.littleEndian)
                append(summary.outflow.bitPattern.littleEndian)
            }
            rows.removeAll(keepingCapacity: true)
            summary = (0, 0, 0, 0, 0)
        }

        try csv.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            let n = bytes.count
            var i = 0
            while i < n, bytes[i] != 10 { i += 1 }
            let header = String(decoding: UnsafeBufferPointer(rebasing: bytes[0..<i]), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ";").map(String.init)
            func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
            guard let cnpjCol = column("CNPJ_FUNDO_CLASSE", "CNPJ_FUNDO"), let dateCol = column("DT_COMPTC"),
                  let quotaCol = column("VL_QUOTA") else { throw MarketDataError.badResponse("a CVM daily report") }
            let subCol = column("ID_SUBCLASSE"), assetsCol = column("VL_PATRIM_LIQ"), holdersCol = column("NR_COTST")
            let inCol = column("CAPTC_DIA"), outCol = column("RESG_DIA")
            i += 1

            let fieldCount = header.count
            var starts = [Int](repeating: 0, count: fieldCount + 1)
            var lineKey: [UInt8] = []
            func double(_ col: Int?) -> Double {
                guard let col, starts[col + 1] - 1 > starts[col] else { return 0 }
                return raw.baseAddress!.advanced(by: starts[col]).withMemoryRebound(to: CChar.self, capacity: 1) { strtod($0, nil) }
            }
            while i < n {
                var field = 0
                starts[0] = i
                while i < n, bytes[i] != 10 {
                    if bytes[i] == 59, field < fieldCount - 1 { field += 1; starts[field] = i + 1 }
                    i += 1
                }
                starts[field + 1] = i + 1  // end of the last field, as if followed by a separator
                i += 1
                guard field == fieldCount - 1 else { continue }

                lineKey.removeAll(keepingCapacity: true)
                for j in starts[cnpjCol]..<(starts[cnpjCol + 1] - 1) where bytes[j] >= 48 && bytes[j] <= 57 { lineKey.append(bytes[j]) }
                if let subCol, starts[subCol + 1] - 1 > starts[subCol] {
                    lineKey.append(124)  // "|"
                    lineKey.append(contentsOf: bytes[starts[subCol]..<(starts[subCol + 1] - 1)])
                }
                if lineKey != key { flush(); key = lineKey }

                // DT_COMPTC is yyyy-mm-dd; keep the day.
                let d = starts[dateCol]
                guard starts[dateCol + 1] - d >= 10 else { continue }
                let day = (bytes[d + 8] &- 48) &* 10 &+ (bytes[d + 9] &- 48)
                guard day >= 1, day <= 31 else { continue }
                let quota = double(quotaCol)
                if quota > 0 { rows.append((day, quota)) }
                summary.inflow += double(inCol)
                summary.outflow += double(outCol)
                if day >= summary.lastDay {
                    summary.lastDay = day
                    summary.netAssets = double(assetsCol)
                    summary.shareholders = UInt32(clamping: Int(double(holdersCol)))
                }
            }
            flush()
        }
        return out
    }

    private static func readCompact(_ data: Data, month: Int, ids: Set<String>) -> MonthData {
        var result = MonthData()
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            func double(_ at: Int) -> Double { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt64.self))) }
            var i = 0
            while i < bytes.count {
                let keyLength = Int(bytes[i])
                let key = String(decoding: UnsafeBufferPointer(rebasing: bytes[(i + 1)..<(i + 1 + keyLength)]), as: UTF8.self)
                i += 1 + keyLength
                let count = Int(bytes[i])
                i += 1
                if ids.contains(key) {
                    var rows: [(day: Int, quota: Double)] = []
                    for r in 0..<count {
                        let at = i + r * 9
                        rows.append((month * 100 + Int(bytes[at]), double(at + 1)))
                    }
                    let s = i + count * 9
                    result.quotas[key, default: []].append(contentsOf: rows)
                    result.summaries[key] = MonthSummary(
                        netAssets: double(s),
                        shareholders: Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: s + 8, as: UInt32.self))),
                        inflow: double(s + 12),
                        outflow: double(s + 20)
                    )
                }
                i += count * 9 + 28
            }
        }
        return result
    }

    // MARK: - FIDC monthly reports

    /// Month-end share prices of FIDCs (receivables funds), which only report monthly. For a class with several
    /// series, the one with the most shares outstanding (normally the senior one). Keyed by CNPJ digits.
    static func fidcQuotas(month: Int, for cnpjs: Set<String>) async -> [String: (day: Int, quota: Double)] {
        let url = cacheDirectory.appendingPathComponent("fidc-\(month).csv")
        let missingMarker = cacheDirectory.appendingPathComponent("fidc-\(month).missing")
        let fresh = age(of: url).map { !isRecent(month) || $0 < 86_400 } ?? false
        if !fresh, age(of: missingMarker).map({ $0 > 86_400 }) ?? true {
            // Only the share-price table is kept (~1 MB of the ~3 MB archive).
            if let zip = try? await download("https://dados.cvm.gov.br/dados/FIDC/DOC/INF_MENSAL/DADOS/inf_mensal_fidc_\(month).zip") {
                defer { try? FileManager.default.removeItem(at: zip) }
                if let table = try? unzip(zip, entry: "inf_mensal_fidc_tab_X_2_\(month).csv") { try? table.write(to: url, options: .atomic) }
            } else if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: missingMarker.path, contents: nil)
            }
        }
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            let table = Table(data)
            var best: [String: (day: Int, quota: Double, shares: Double)] = [:]
            for row in table.rows {
                guard let cnpj = table.value(row, "CNPJ_FUNDO_CLASSE")?.filter(\.isNumber), cnpjs.contains(cnpj),
                      let quota = table.value(row, "TAB_X_VL_COTA").flatMap(Double.init), quota > 0,
                      let day = table.value(row, "DT_COMPTC").flatMap({ Int($0.replacingOccurrences(of: "-", with: "")) })
                else { continue }
                let shares = table.value(row, "TAB_X_QT_COTA").flatMap(Double.init) ?? 0
                if shares >= best[cnpj]?.shares ?? -1 { best[cnpj] = (day, quota, shares) }
            }
            return best.mapValues { ($0.day, $0.quota) }
        }.value
    }

    // MARK: - Fact sheets

    /// The fund's most recent fact sheet from the last 12 months of filings, or nil if it hasn't filed one.
    static func lamina(for fund: FundInfo) async -> Lamina? {
        let cnpj = fund.formattedCNPJ, subclass = fund.subclass ?? ""
        var months: [Int] = [], month = DayKey.from(.now) / 100
        for _ in 0..<12 {
            month = month % 100 == 1 ? (month / 100 - 1) * 100 + 12 : month - 1
            months.append(month)
        }
        // Fetch the archives side by side, then look through them newest first.
        let archives = await withTaskGroup(of: (Int, URL?).self) { group in
            for m in months { group.addTask { (m, await laminaArchive(m)) } }
            return await group.reduce(into: [Int: URL]()) { $0[$1.0] = $1.1 }
        }
        for month in months {
            guard let zip = archives[month] else { continue }
            let found = await Task.detached(priority: .userInitiated) { () -> Lamina? in
                // Most funds aren't in most months: a byte search skips the parse.
                guard let data = try? unzip(zip, entry: "lamina_fi_\(month).csv"), data.range(of: Data(cnpj.utf8)) != nil else { return nil }
                let table = Table(data)
                func matches(_ t: Table, _ row: [Substring]) -> Bool {
                    t.value(row, "CNPJ_FUNDO_CLASSE") == cnpj && (t.value(row, "ID_SUBCLASSE") ?? "") == subclass
                }
                guard let row = table.rows.last(where: { matches(table, $0) }) else { return nil }
                var fields: [String: String] = [:]
                for (name, i) in table.columns where i < row.count { fields[name] = String(row[i]) }

                var portfolio: [(asset: String, percent: Double)] = []
                if let data = try? unzip(zip, entry: "lamina_fi_carteira_\(month).csv") {
                    let t = Table(data)
                    for r in t.rows where matches(t, r) {
                        if let asset = t.value(r, "TP_ATIVO"), let p = t.value(r, "PR_PL_ATIVO").flatMap(Double.init) { portfolio.append((asset, p)) }
                    }
                }
                var yearly: [(year: Int, fund: Double?, index: Double?)] = []
                if let data = try? unzip(zip, entry: "lamina_fi_rentab_ano_\(month).csv") {
                    let t = Table(data)
                    for r in t.rows where matches(t, r) {
                        guard let year = t.value(r, "ANO_RENTAB").flatMap(Int.init) else { continue }
                        yearly.append((year, t.value(r, "PR_RENTAB_ANO").flatMap(Double.init), t.value(r, "PR_VARIACAO_INDICE_REFER_ANO").flatMap(Double.init)))
                    }
                }
                let date = fields["DT_COMPTC"].map { Int($0.replacingOccurrences(of: "-", with: "")) ?? 0 } ?? month * 100
                return Lamina(date: date, fields: fields, portfolio: portfolio.sorted { $0.percent > $1.percent }, yearly: yearly.sorted { $0.year > $1.year })
            }.value
            if let found { return found }
        }
        return nil
    }

    /// Fact-sheet archives are small (~650 KB) and kept; recent months are re-checked daily.
    private static func laminaArchive(_ month: Int) async -> URL? {
        let url = cacheDirectory.appendingPathComponent("lamina-\(month).zip")
        let missingMarker = cacheDirectory.appendingPathComponent("lamina-\(month).missing")
        if let age = age(of: url), !isRecent(month) || age < 86_400 { return url }
        if let age = age(of: missingMarker), age < 86_400 { return nil }
        do {
            guard let zip = try await download("\(base)/DOC/LAMINA/DADOS/lamina_fi_\(month).zip") else {
                FileManager.default.createFile(atPath: missingMarker.path, contents: nil)
                return nil
            }
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: zip, to: url)
            return url
        } catch {
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    // MARK: - Files

    /// Downloads to a temporary file in the cache directory; nil when CVM has no such file (404).
    private static func download(_ address: String) async throws -> URL? {
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 120
        let (temp, response) = try await URLSession.shared.download(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw MarketDataError.badResponse("CVM (HTTP \(code))") }
        let destination = cacheDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    /// CVM ships zips; the system `unzip` streams one entry out without touching the disk.
    private static func unzip(_ zip: URL, entry: String? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path] + (entry.map { [$0] } ?? [])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw MarketDataError.badResponse("a CVM archive") }
        return data
    }

    private static func age(of url: URL) -> TimeInterval? {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        return Date.now.timeIntervalSince(date)
    }
}
