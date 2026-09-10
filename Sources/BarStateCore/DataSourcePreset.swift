import Foundation

public enum DataSourceProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek
    case openRouter
    case siliconFlow

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .siliconFlow: "SiliconFlow"
        }
    }
    public var metrics: [PresetMetric] {
        self == .openRouter ? [.usageDaily, .usageMonthly, .remainingBudget] : [.balance]
    }
    public var endpoint: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com/user/balance"
        case .openRouter: "https://openrouter.ai/api/v1/key"
        case .siliconFlow: "https://api.siliconflow.cn/v1/user/info"
        }
    }
    public var shortName: String {
        switch self {
        case .deepSeek: "DS"
        case .openRouter: "OR"
        case .siliconFlow: "SF"
        }
    }
}

public enum PresetMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case balance
    case usageDaily
    case usageMonthly
    case remainingBudget

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .balance: L10n.string("preset.metric.balance")
        case .usageDaily: L10n.string("preset.metric.usageDaily")
        case .usageMonthly: L10n.string("preset.metric.usageMonthly")
        case .remainingBudget: L10n.string("preset.metric.remainingBudget")
        }
    }
}

public enum PresetCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case cny = "CNY"
    case usd = "USD"
    public var id: String { rawValue }
}

/// Identifies a provider and metric independently of the HTTP transport.
public struct DataSourcePreset: Codable, Equatable, Sendable {
    public var provider: DataSourceProvider
    public var metric: PresetMetric
    public var apiKey: String
    public var currency: PresetCurrency

    public init(
        provider: DataSourceProvider,
        metric: PresetMetric? = nil,
        apiKey: String = "",
        currency: PresetCurrency = .cny
    ) {
        self.provider = provider
        self.metric = metric ?? (provider == .openRouter ? .usageDaily : .balance)
        self.apiKey = apiKey
        self.currency = currency
    }

    public var unit: String {
        switch provider {
        case .deepSeek: currency.rawValue
        case .openRouter: "USD"
        case .siliconFlow: "CNY"
        }
    }
    public var defaultDisplayTemplate: String {
        "\(provider.shortName) \(Monitor.valuePlaceholder) \(unit)"
    }

    public func makeRequest(timeout: TimeInterval) throws -> URLRequest {
        guard provider.metrics.contains(metric) else { throw MonitoringError.presetMetricUnsupported }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MonitoringError.presetKeyRequired }
        guard !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw MonitoringError.presetKeyInvalid
        }
        guard let url = URL(string: provider.endpoint) else { throw MonitoringError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Monitor.normalizedRequestTimeout(timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func number(from data: Data) throws -> Double {
        guard provider.metrics.contains(metric) else { throw MonitoringError.presetMetricUnsupported }
        do {
            let decoder = JSONDecoder()
            let value: ProviderNumber?
            switch provider {
            case .deepSeek:
                let envelope = try decoder.decode(DeepSeekBalance.self, from: data)
                let matches = envelope.balance_infos.filter { $0.currency == currency.rawValue }
                guard matches.count == 1 else { throw MonitoringError.presetCurrencyUnavailable }
                value = matches[0].total_balance
            case .openRouter:
                let envelope = try decoder.decode(OpenRouterUsage.self, from: data)
                switch metric {
                case .usageDaily: value = envelope.data.usage_daily
                case .usageMonthly: value = envelope.data.usage_monthly
                case .remainingBudget:
                    guard envelope.data.limit != nil else { throw MonitoringError.presetBudgetUnset }
                    value = envelope.data.limit_remaining
                case .balance: throw MonitoringError.presetMetricUnsupported
                }
            case .siliconFlow:
                let envelope = try decoder.decode(SiliconFlowBalance.self, from: data)
                guard envelope.code == 20000, envelope.status else {
                    throw MonitoringError.presetServiceRejected
                }
                value = envelope.data?.totalBalance
            }
            guard let value else { throw MonitoringError.presetValueMissing }
            guard value.value.isFinite else { throw MonitoringError.nonFiniteNumber }
            return value.value
        } catch let error as MonitoringError {
            throw error
        } catch {
            // Provider payloads can contain account identifiers; do not echo them in errors.
            throw MonitoringError.presetInvalidData
        }
    }

    /// Retain only documented numeric fields needed to retest a selected metric.
    public func sanitizedSnapshotData(from data: Data) -> Data {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Data("{}".utf8)
        }
        let sanitized: [String: Any]
        switch provider {
        case .deepSeek:
            let balances = (root["balance_infos"] as? [[String: Any]] ?? []).map {
                $0.filter { ["currency", "total_balance"].contains($0.key) }
            }
            sanitized = ["balance_infos": balances]
        case .openRouter:
            let values = (root["data"] as? [String: Any] ?? [:]).filter {
                ["usage_daily", "usage_monthly", "limit", "limit_remaining"].contains($0.key)
            }
            sanitized = ["data": values]
        case .siliconFlow:
            let values = (root["data"] as? [String: Any] ?? [:]).filter { $0.key == "totalBalance" }
            sanitized = [
                "code": root["code"] ?? NSNull(),
                "status": root["status"] ?? NSNull(),
                "data": values
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }
}

private struct ProviderNumber: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let value = Double(string) else { throw MonitoringError.presetInvalidData }
            self.value = value
        } else {
            value = try container.decode(Double.self)
        }
        guard value.isFinite else { throw MonitoringError.nonFiniteNumber }
    }
}

private struct DeepSeekBalance: Decodable {
    struct Balance: Decodable {
        let currency: String
        let total_balance: ProviderNumber?
    }
    let balance_infos: [Balance]
}

private struct OpenRouterUsage: Decodable {
    struct Usage: Decodable {
        let usage_daily: ProviderNumber?
        let usage_monthly: ProviderNumber?
        let limit: ProviderNumber?
        let limit_remaining: ProviderNumber?
    }
    let data: Usage
}

private struct SiliconFlowBalance: Decodable {
    struct Balance: Decodable { let totalBalance: ProviderNumber? }
    let code: Int
    let status: Bool
    let data: Balance?
}
