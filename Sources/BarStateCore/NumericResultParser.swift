import Foundation

enum NumericResultParser {
    static func parse(_ string: String) throws -> Double {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let value = Double(normalized) else {
            throw MonitoringError.resultIsNotNumber
        }
        return try validate(value)
    }

    static func validate(_ value: Double) throws -> Double {
        guard value.isFinite else { throw MonitoringError.nonFiniteNumber }
        return value
    }
}
