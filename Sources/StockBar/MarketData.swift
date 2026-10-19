import Foundation

enum MarketDataError: LocalizedError {
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let what): "Couldn't read data for \(what)"
        }
    }
}

extension Calendar {
    static let b3: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return cal
    }()
}

enum MarketData {
    /// B3 tickers are 4 letters plus 1–2 digits (PETR4, BPAC11, AXIA17), optionally F for the fractional market.
    /// Anything else (IVV, QQQ, BRK-B) is a US ticker, priced in dollars.
    static func isB3(_ ticker: String) -> Bool {
        ticker.uppercased().range(of: #"^[A-Z]{4}[0-9]{1,2}F?$"#, options: .regularExpression) != nil
    }

    /// Yahoo's symbol for USD/BRL.
    static let dollarSymbol = "BRL=X"
    /// S&P 500 total return (dividends reinvested), in dollars.
    static let sp500Symbol = "^SP500TR"
    /// IFIX live value; its history comes from B3 (Yahoo only has today).
    static let ifixSymbol = "IFIX.SA"
    /// Fetched with daily history; IFIX only intraday.
    static let referenceSymbols: Set<String> = [dollarSymbol, sp500Symbol]

    /// Dollar-priced symbols that need converting to reais.
    static func isInDollars(_ symbol: String) -> Bool {
        !isB3(symbol) && symbol != dollarSymbol && symbol != ifixSymbol
    }

    static func displayName(_ symbol: String) -> String {
        switch symbol {
        case dollarSymbol: "USD/BRL"
        case sp500Symbol: "S&P 500"
        case ifixSymbol: "IFIX"
        default: symbol
        }
    }

    /// B3 tickers go to Yahoo with a ".SA" suffix; fractional tickers (PETR4F) map to the regular one.
    static func yahooSymbol(for ticker: String) -> String {
        var t = ticker.uppercased()
        guard isB3(t) else { return t }
        if t.hasSuffix("F") { t.removeLast() }
        return t + ".SA"
    }

    /// Daily adjusted closes from `start` until today.
    static func history(for ticker: String, from start: Date) async throws -> PriceHistory {
        let symbol = yahooSymbol(for: ticker)
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let period1 = Int(start.timeIntervalSince1970)
        let period2 = Int(Date.now.timeIntervalSince1970) + 86_400
        var request = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?period1=\(period1)&period2=\(period2)&interval=1d&events=div,split")!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        struct Response: Decodable {
            struct Chart: Decodable { var result: [Result]? }
            struct Result: Decodable {
                var meta: Meta
                var timestamp: [TimeInterval]?
                var indicators: Indicators
            }
            struct Meta: Decodable { var shortName: String?; var longName: String? }
            struct Indicators: Decodable {
                struct Quote: Decodable { var close: [Double?]? }
                struct AdjClose: Decodable { var adjclose: [Double?]? }
                var quote: [Quote]?
                var adjclose: [AdjClose]?
            }
            var chart: Chart
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let result = try JSONDecoder().decode(Response.self, from: data).chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators.adjclose?.first?.adjclose ?? result.indicators.quote?.first?.close
        else { throw MarketDataError.badResponse(ticker) }

        var history = PriceHistory(days: [], prices: [], name: result.meta.longName ?? result.meta.shortName)
        for (time, close) in zip(timestamps, closes) {
            guard let close, close > 0 else { continue }
            let day = DayKey.from(Date(timeIntervalSince1970: time), calendar: .b3)
            if history.days.last == day {
                history.prices[history.prices.count - 1] = close
            } else {
                history.days.append(day)
                history.prices.append(close)
            }
        }
        guard !history.days.isEmpty else { throw MarketDataError.badResponse(ticker) }
        return history
    }

    /// Today's (or the last session's) 5-minute prices, unadjusted.
    static func intraday(for ticker: String) async throws -> IntradaySeries {
        let symbol = yahooSymbol(for: ticker)
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        var request = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=5m")!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        struct Response: Decodable {
            struct Chart: Decodable { var result: [Result]? }
            struct Result: Decodable {
                var meta: Meta
                var timestamp: [TimeInterval]?
                var indicators: Indicators
            }
            struct Meta: Decodable {
                var regularMarketPrice: Double?
                var regularMarketTime: TimeInterval?
                var chartPreviousClose: Double?
                var previousClose: Double?
            }
            struct Indicators: Decodable {
                struct Quote: Decodable { var close: [Double?]? }
                var quote: [Quote]?
            }
            var chart: Chart
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let result = try JSONDecoder().decode(Response.self, from: data).chart.result?.first,
              let price = result.meta.regularMarketPrice,
              let time = result.meta.regularMarketTime,
              let previousClose = result.meta.chartPreviousClose ?? result.meta.previousClose
        else { throw MarketDataError.badResponse(ticker) }

        var series = IntradaySeries(
            day: DayKey.from(Date(timeIntervalSince1970: time), calendar: .b3),
            times: [], prices: [], previousClose: previousClose, last: price
        )
        for (t, close) in zip(result.timestamp ?? [], result.indicators.quote?.first?.close ?? []) {
            guard let close, close > 0 else { continue }
            series.times.append(Date(timeIntervalSince1970: t))
            series.prices.append(close)
        }
        return series
    }

    /// Daily closes of a B3 index (e.g. IFIX) from B3's index statistics, one request per year.
    static func b3IndexHistory(_ index: String, fromYear: Int, toYear: Int) async throws -> PriceHistory {
        var history = PriceHistory(days: [], prices: [], name: index)
        for year in fromYear...toYear {
            for point in try await b3IndexYear(index, year: year) {
                history.days.append(point.day)
                history.prices.append(point.value)
            }
        }
        return history
    }

    private static func b3IndexYear(_ index: String, year: Int, attempts: Int = 4) async throws -> [(day: Int, value: Double)] {
        let query = Data(#"{"index":"\#(index)","language":"pt-br","year":"\#(year)"}"#.utf8).base64EncodedString()
        let url = URL(string: "https://sistemaswebb3-listados.b3.com.br/indexStatisticsProxy/IndexCall/GetPortfolioDay/\(query)")!

        // One row per day of the month, one column (rateValue1…12) per month, values like "3.876,65".
        struct Response: Decodable {
            struct Row: Decodable {
                var day: Int
                var months: [Int: String]
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: AnyKey.self)
                    day = try c.decode(Int.self, forKey: AnyKey("day"))
                    months = [:]
                    for m in 1...12 {
                        if let v = try c.decodeIfPresent(String.self, forKey: AnyKey("rateValue\(m)")) { months[m] = v }
                    }
                }
            }
            var results: [Row]
        }

        for attempt in 1...attempts {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let response = try? JSONDecoder().decode(Response.self, from: data) {
                var points: [(day: Int, value: Double)] = []
                for row in response.results {
                    for (month, text) in row.months {
                        if let value = parseNumber(text) { points.append((year * 10_000 + month * 100 + row.day, value)) }
                    }
                }
                return points.sorted { $0.day < $1.day }
            }
            if attempt < attempts { try await Task.sleep(for: .seconds(Double(attempt) * 1.5)) }
        }
        throw MarketDataError.badResponse(index)
    }

    /// Banco Central SGS series: 12 = CDI (% per day), 433 = IPCA (% per month).
    /// The API often rejects or times out on long ranges, so it's fetched a year at a time with retries.
    static func bcbSeries(_ code: Int, from start: Date, to end: Date = .now) async throws -> [RatePoint] {
        let cal = Calendar(identifier: .gregorian)
        var points: [RatePoint] = []
        var chunkStart = start
        while chunkStart <= end {
            let chunkEnd = min(cal.date(byAdding: .day, value: 364, to: chunkStart)!, end)
            points += try await bcbChunk(code, from: chunkStart, to: chunkEnd)
            chunkStart = cal.date(byAdding: .day, value: 1, to: chunkEnd)!
        }
        return points.sorted { $0.day < $1.day }
    }

    private static func bcbChunk(_ code: Int, from start: Date, to end: Date, attempts: Int = 5) async throws -> [RatePoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        let url = URL(string: "https://api.bcb.gov.br/dados/serie/bcdata.sgs.\(code)/dados?formato=json&dataInicial=\(formatter.string(from: start))&dataFinal=\(formatter.string(from: end))")!

        struct Row: Decodable { var data: String; var valor: String }

        for attempt in 1...attempts {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if let (data, response) = try? await URLSession.shared.data(for: request) {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 404 means no observations in the range yet (e.g. IPCA for the current month).
                if status == 404 { return [] }
                // Failures often come back as a 200 with an HTML error page, so only parsed JSON counts.
                if status == 200, let rows = try? JSONDecoder().decode([Row].self, from: data) {
                    return rows.compactMap { row in
                        guard let day = DayKey.parse(row.data), let rate = Double(row.valor) else { return nil }
                        return RatePoint(day: day, rate: rate)
                    }
                }
            }
            if attempt < attempts { try await Task.sleep(for: .seconds(Double(attempt) * 1.5)) }
        }
        throw MarketDataError.badResponse(code == 12 ? "CDI" : "IPCA")
    }
}

/// Cumulative CDI/IPCA level, so growth between two days is `level(b) / level(a)`.
struct Benchmark {
    enum Kind { case daily, monthly }

    private let points: [RatePoint]
    private let prefix: [Double]  // prefix[i] = Π (1 + rate/100) for points[..<i]
    private let kind: Kind

    init(points: [RatePoint], kind: Kind) {
        self.points = points
        self.kind = kind
        var factors = [1.0]
        for p in points { factors.append(factors.last! * (1 + p.rate / 100)) }
        prefix = factors
    }

    var isEmpty: Bool { points.isEmpty }
    var latestRate: Double? { points.last?.rate }

    func level(at day: Int) -> Double {
        switch kind {
        case .daily:
            // CDI earned on each business day before `day`.
            return prefix[firstIndex { $0.day >= day }]
        case .monthly:
            // Full months before `day`'s month, plus that month pro rata by calendar days
            // (0% while IBGE hasn't published it yet).
            let month = day / 100
            let i = firstIndex { $0.day / 100 >= month }
            var level = prefix[i]
            if i < points.count, points[i].day / 100 == month {
                let fraction = Double(day % 100 - 1) / Double(DayKey.daysInMonth(day))
                level *= pow(1 + points[i].rate / 100, fraction)
            }
            return level
        }
    }

    private func firstIndex(where predicate: (RatePoint) -> Bool) -> Int {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if predicate(points[mid]) { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
