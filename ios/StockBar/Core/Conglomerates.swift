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

