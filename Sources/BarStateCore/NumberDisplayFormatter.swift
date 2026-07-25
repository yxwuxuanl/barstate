import Foundation

public enum NumberDisplayFormatter {
    public static func string(from value: Double, locale: Locale = .current) -> String {
        guard value.isFinite else { return "--" }

        let magnitude = abs(value)
        if magnitude != 0, magnitude >= 1_000_000_000_000 || magnitude < 0.000001 {
            return String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
