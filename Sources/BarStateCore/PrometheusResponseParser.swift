import CoreFoundation
import Foundation

public enum PrometheusResponseParser {
    public static func number(from data: Data) throws -> Double {
        let root = try responseObject(from: data)
        guard root["status"] is String else {
            throw MonitoringError.prometheusQueryFailed(
                "invalid_response",
                L10n.string("error.prometheus_invalid_envelope")
            )
        }
        if let apiError = apiError(in: root) {
            throw apiError
        }

        guard let dataObject = root["data"] as? [String: Any],
              let resultType = dataObject["resultType"] as? String
        else {
            throw MonitoringError.prometheusMissingValue
        }

        switch resultType {
        case "scalar":
            guard let sample = dataObject["result"] as? [Any] else {
                throw MonitoringError.prometheusMissingValue
            }
            return try number(fromSample: sample)

        case "vector":
            guard let result = dataObject["result"] as? [Any] else {
                throw MonitoringError.prometheusMissingValue
            }
            guard !result.isEmpty else {
                throw MonitoringError.prometheusEmptyResult
            }
            guard result.count == 1 else {
                throw MonitoringError.prometheusMultipleSeries(result.count)
            }
            guard let series = result[0] as? [String: Any] else {
                throw MonitoringError.prometheusMissingValue
            }
            if series["histogram"] != nil {
                throw MonitoringError.prometheusUnsupportedResultType("histogram")
            }
            guard let sample = series["value"] as? [Any] else {
                throw MonitoringError.prometheusMissingValue
            }
            return try number(fromSample: sample)

        default:
            throw MonitoringError.prometheusUnsupportedResultType(resultType)
        }
    }

    public static func apiError(from data: Data) -> MonitoringError? {
        guard let root = try? responseObject(from: data) else { return nil }
        return apiError(in: root)
    }

    private static func responseObject(from data: Data) throws -> [String: Any] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw MonitoringError.invalidJSON(error.localizedDescription)
        }
        guard let object = json as? [String: Any] else {
            throw MonitoringError.invalidJSON(L10n.string("error.prometheus_invalid_envelope"))
        }
        return object
    }

    private static func apiError(in root: [String: Any]) -> MonitoringError? {
        guard let status = root["status"] as? String else { return nil }
        guard status != "success" else { return nil }
        let errorType = (root["errorType"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let message = (root["error"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let resolvedType = errorType.flatMap { $0.isEmpty ? nil : $0 } ?? status
        let resolvedMessage = message.flatMap { $0.isEmpty ? nil : $0 }
            ?? L10n.string("error.prometheus_unknown_error")
        return .prometheusQueryFailed(resolvedType, resolvedMessage)
    }

    private static func number(fromSample sample: [Any]) throws -> Double {
        guard sample.count >= 2 else {
            throw MonitoringError.prometheusMissingValue
        }
        let rawValue = sample[1]
        if let number = rawValue as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID()
        {
            return try NumericResultParser.validate(number.doubleValue)
        }
        if let string = rawValue as? String {
            return try NumericResultParser.parse(string)
        }
        throw MonitoringError.prometheusMissingValue
    }
}
