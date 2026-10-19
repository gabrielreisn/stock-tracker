import Foundation
import SwiftUI

private let brazil = Locale(identifier: "pt_BR")

extension Double {
    var signedPercent: String {
        formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(brazil))
    }

    /// Difference between two returns, in percentage points.
    var signedPoints: String {
        (self * 100).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()).locale(brazil)) + " p.p."
    }

    var percent: String { formatted(.percent.precision(.fractionLength(1)).locale(brazil)) }

    var quantity: String { formatted(.number.precision(.fractionLength(0...5)).locale(brazil)) }

    /// For editable fields: no thousands separator, so it parses back unambiguously.
    var editableQuantity: String { formatted(.number.precision(.fractionLength(0...5)).grouping(.never).locale(brazil)) }

    var gainColor: Color { self > 0.0000001 ? .green : self < -0.0000001 ? .red : .secondary }
}

/// Accepts "1.234,5", "1234,5", "1234.5", and "1.143" as Brazilian thousands (1143).
func parseNumber(_ text: String) -> Double? {
    var t = text.trimmingCharacters(in: .whitespaces)
    if t.contains(",") || t.range(of: #"^[1-9]\d{0,2}(\.\d{3})+$"#, options: .regularExpression) != nil {
        t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
    }
    return Double(t)
}
