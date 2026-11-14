import Foundation

/// Money in minor units as Int64. For VND the minor unit is 1 ₫ (no decimals).
/// No Float/Double is used anywhere in financial arithmetic.
public struct Money: Hashable, Comparable, Codable, Sendable {
    public var minor: Int64
    public init(_ minor: Int64) { self.minor = minor }
    public static func < (a: Money, b: Money) -> Bool { a.minor < b.minor }
    public static func + (a: Money, b: Money) -> Money { Money(a.minor + b.minor) }
    public static func - (a: Money, b: Money) -> Money { Money(a.minor - b.minor) }

    /// "1.250.000 ₫", negatives as "-50.000 ₫".
    public func formatted(symbol: String = "₫") -> String {
        let digits = String(minor.magnitude)
        var out = "", count = 0
        for ch in digits.reversed() {
            if count > 0 && count % 3 == 0 { out.append(".") }
            out.append(ch); count += 1
        }
        return (minor < 0 ? "-" : "") + String(out.reversed()) + " " + symbol
    }

    /// Parses user input such as "1.250.000", "1,250,000" or "50000". Digits only; rejects anything else.
    public static func parse(_ text: String) -> Money? {
        let digits = text.filter { !".,  _".contains($0) }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let v = Int64(digits) else { return nil }
        return Money(v)
    }

    /// Percentage as an integer (0...), using integer math; used for budgets/savings rate.
    public static func percent(_ part: Money, of whole: Money) -> Int {
        guard whole.minor > 0 else { return 0 }
        return Int((Int64(part.minor) * 100) / whole.minor)
    }
}
