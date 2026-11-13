import XCTest
import UIKit
import SwiftUI
@testable import StockBar

final class FinancialTests: XCTestCase {
    @MainActor func testCymbaIdentityAndExpoPalette() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Cymba Native")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.cymba.native")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        XCTAssertEqual(urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }, ["cymba-native"])
        let palette: [(Color, UInt32, UInt32)] = [
            (CymbaTheme.background, 0xffffff, 0x0a0a0a),
            (CymbaTheme.surface, 0xf2f2f4, 0x1a1a1c),
            (CymbaTheme.selected, 0xe4e4e7, 0x2a2a2e),
            (CymbaTheme.text, 0x171717, 0xededed),
            (CymbaTheme.secondary, 0x63636b, 0xa1a1aa),
            (CymbaTheme.accent, 0x2563eb, 0x2563eb)
        ]
        for (color, light, dark) in palette {
            for (style, expected) in [(UIUserInterfaceStyle.light, light), (.dark, dark)] {
                let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &alpha))
                XCTAssertEqual(r, CGFloat((expected >> 16) & 255) / 255, accuracy: 0.001)
                XCTAssertEqual(g, CGFloat((expected >> 8) & 255) / 255, accuracy: 0.001)
                XCTAssertEqual(b, CGFloat(expected & 255) / 255, accuracy: 0.001)
            }
        }
    }

    func testBrazilianNumberInput() {
        XCTAssertEqual(parseNumber("1.234,50"), 1234.5)
        XCTAssertEqual(parseNumber("1234.50"), 1234.5)
        XCTAssertEqual(parseNumber("1.143"), 1143)
        XCTAssertNil(parseNumber("no price"))
    }
    func testFGCAndTaxEligibility() {
        XCTAssertTrue(BondKind.cdb.isFGCCovered)
        XCTAssertFalse(BondKind.cri.isFGCCovered)
        XCTAssertTrue(BondKind.lci.isTaxExempt)
        XCTAssertFalse(BondKind.cdb.isTaxExempt)
    }
    func testFixedBondTaxAndMaturity() {
        var bond = Bond(kind: .cdb, issuer: "Test", code: "A", issueDay: 20250102, maturityDay: 20260102, indexer: .fixed, rate: 12, quantity: 10)
        let pricer = BondPricer(cdi: [], ipca: [:])
        let value = pricer.value(bond, on: 20260102)
        let expectedGross = 10000 * pow(1.12, Double(BusinessDays.count(from: 20250102, to: 20260102)) / 252)
        XCTAssertEqual(value.gross, expectedGross, accuracy: 0.01)
        XCTAssertEqual(value.incomeTax, (expectedGross - 10000) * 0.175, accuracy: 0.01)
        XCTAssertEqual(value.iof, 0)
        XCTAssertEqual(pricer.value(bond, on: 20270102).gross, value.gross, accuracy: 0.01)
        bond.kind = .lci
        XCTAssertEqual(pricer.value(bond, on: 20260102).incomeTax, 0)
    }
    func testZipEntriesStoredDeflatedAndMalformed() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cvm", withExtension: "zip", subdirectory: "Fixtures") ?? Bundle(for: Self.self).url(forResource: "cvm", withExtension: "zip"))
        XCTAssertEqual(String(decoding: try ZIPReader.read(url, entry: "registro_fundo.csv"), as: UTF8.self), "CNPJ;NOME\n123;Fundo A\n")
        XCTAssertEqual(String(decoding: try ZIPReader.read(url, entry: "registro_classe.csv"), as: UTF8.self), "CNPJ;NOME\n456;Fundo B\n")
        XCTAssertThrowsError(try ZIPReader.read(url, entry: "missing.csv"))
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: invalid) }
        try Data(repeating: 0, count: 100).write(to: invalid)
        XCTAssertThrowsError(try ZIPReader.read(invalid))
        var corrupted = try Data(contentsOf: url)
        let payload = Data("456;Fundo B".utf8)
        let range = try XCTUnwrap(corrupted.range(of: payload))
        corrupted[range.lowerBound] ^= 1
        try corrupted.write(to: invalid)
        XCTAssertThrowsError(try ZIPReader.read(invalid, entry: "registro_classe.csv"))
    }
    @MainActor func testImportRequiresReportedBondTerms() throws {
        let json = #"{"id":"position","itemId":"bank","type":"FIXED_INCOME","subtype":"CDB","code":"CDB-123","quantity":10,"amountOriginal":10000,"issueDate":"2025-01-02","dueDate":"2027-01-02","rateType":"CDI","rate":100}"#
        var inv = try JSONDecoder().decode(PluggyInvestment.self, from: Data(json.utf8))
        let bond = try XCTUnwrap(OpenFinanceImporter.bond(inv, quantity: 10, cost: inv.averagePrice))
        XCTAssertEqual(bond.unitPrice, 1000)
        XCTAssertEqual(bond.indexer, .cdi)
        inv.dueDate = nil
        XCTAssertNil(OpenFinanceImporter.bond(inv, quantity: 10, cost: inv.averagePrice))
        inv.dueDate = "2027-01-02"; inv.subtype = "UNKNOWN"
        XCTAssertNil(OpenFinanceImporter.bond(inv, quantity: 10, cost: inv.averagePrice))
        inv.subtype = "CDB"; inv.amountOriginal = nil
        XCTAssertNil(OpenFinanceImporter.bond(inv, quantity: 10, cost: inv.averagePrice))
    }
    func testImportCostAndPriceAlertDirections() throws {
        let inv = try JSONDecoder().decode(PluggyInvestment.self, from: Data(#"{"id":"stock","quantity":20,"amount":240,"amountProfit":40}"#.utf8))
        XCTAssertEqual(inv.averagePrice, 10)
        XCTAssertTrue(PriceAlert(ticker: "PETR4", target: 30, kind: .buy).isMet(by: 29))
        XCTAssertFalse(PriceAlert(ticker: "PETR4", target: 30, kind: .buy).isMet(by: 31))
        XCTAssertTrue(PriceAlert(ticker: "PETR4", target: 30, kind: .sell).isMet(by: 31))
    }
    @MainActor func testMerchantRulesNormalizeAccentsAndPunctuation() {
        XCTAssertEqual(ExpenseStore.merchantKey("Café * ABC"), ExpenseStore.merchantKey("CAFE ABC"))
    }
}
