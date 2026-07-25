import Foundation

public enum ParserKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jsonPath
    case javaScript

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jsonPath: "JSONPath"
        case .javaScript: "JavaScript"
        }
    }
}

public struct ParserConfiguration: Codable, Equatable, Sendable {
    public var kind: ParserKind
    public var jsonPath: String
    public var scriptBody: String

    public init(
        kind: ParserKind = .jsonPath,
        jsonPath: String = "$.value",
        scriptBody: String = JavaScriptEvaluator.defaultFunctionSource
    ) {
        self.kind = kind
        self.jsonPath = jsonPath
        self.scriptBody = scriptBody
    }
}

public enum RefreshIntervalUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case seconds
    case minutes
    case hours

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .seconds: L10n.string("monitor.interval.seconds")
        case .minutes: L10n.string("monitor.interval.minutes")
        case .hours: L10n.string("monitor.interval.hours")
        }
    }

    public var secondsMultiplier: TimeInterval {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3_600
        }
    }

    public func seconds(for value: Double) -> TimeInterval {
        value * secondsMultiplier
    }

    public func value(for seconds: TimeInterval) -> Double {
        seconds / secondsMultiplier
    }
}

public struct RequestHeader: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !normalizedName.isEmpty
            && normalizedName.unicodeScalars.allSatisfy(Self.isAllowedNameScalar)
            && !value.contains("\r")
            && !value.contains("\n")
    }

    public var hasSensitiveValue: Bool {
        Self.sensitiveHeaderNames.contains(normalizedName.lowercased())
    }

    private static let sensitiveHeaderNames: Set<String> = [
        "api-key",
        "authorization",
        "cookie",
        "proxy-authorization",
        "x-api-key",
        "x-auth-token"
    ]

    private static func isAllowedNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            true
        default:
            "!#$%&'*+-.^_`|~".unicodeScalars.contains(scalar)
        }
    }

}

public struct MonitorRuntimeState: Codable, Equatable, Sendable {
    public var lastValue: Double?
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var lastResponse: HTTPResponseSnapshot?
    public var consecutiveFailures: Int
    public var lastError: MonitoringError?

    public init(
        lastValue: Double? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastResponse: HTTPResponseSnapshot? = nil,
        lastResponseText: String? = nil,
        lastResponseAt: Date? = nil,
        consecutiveFailures: Int = 0,
        lastError: MonitoringError? = nil
    ) {
        self.lastValue = lastValue
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.lastResponse = lastResponse ?? Self.legacyResponse(
            text: lastResponseText,
            at: lastResponseAt
        )
        self.consecutiveFailures = consecutiveFailures
        self.lastError = lastError
    }

    public var lastResponseText: String? { lastResponse?.bodyText }

    public var lastResponseAt: Date? { lastResponse?.requestedAt }

    public mutating func recordSuccess(
        _ value: Double,
        at date: Date,
        response: HTTPResponseSnapshot? = nil,
        responseText: String? = nil,
        responseAt: Date? = nil
    ) {
        lastValue = value
        lastSuccessAt = date
        lastAttemptAt = date
        consecutiveFailures = 0
        lastError = nil
        recordResponse(response, legacyText: responseText, at: responseAt)
    }

    public mutating func recordFailure(
        _ error: MonitoringError,
        at date: Date,
        response: HTTPResponseSnapshot? = nil,
        responseText: String? = nil,
        responseAt: Date? = nil
    ) {
        lastAttemptAt = date
        consecutiveFailures += 1
        lastError = error
        recordResponse(response, legacyText: responseText, at: responseAt)
    }

    public var displayValue: Double? {
        guard consecutiveFailures < 3 else { return nil }
        return lastValue
    }

    private mutating func recordResponse(
        _ response: HTTPResponseSnapshot?,
        legacyText responseText: String?,
        at responseAt: Date?
    ) {
        if let response {
            lastResponse = response
        } else if let legacy = Self.legacyResponse(text: responseText, at: responseAt) {
            lastResponse = legacy
        }
    }

    private static func legacyResponse(text: String?, at date: Date?) -> HTTPResponseSnapshot? {
        guard let text, let date else { return nil }
        let kind: ResponseBodyKind = (try? JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: [.fragmentsAllowed]
        )) == nil ? .text : .json
        return HTTPResponseSnapshot(
            requestedAt: date,
            bodyText: text,
            bodyKind: kind
        )
    }

    private enum CodingKeys: String, CodingKey {
        case lastValue
        case lastSuccessAt
        case lastAttemptAt
        case lastResponse
        case lastResponseText
        case lastResponseAt
        case consecutiveFailures
        case lastError
        case lastFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastValue = try container.decodeIfPresent(Double.self, forKey: .lastValue)
        lastSuccessAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        lastResponse = try container.decodeIfPresent(HTTPResponseSnapshot.self, forKey: .lastResponse)
        if lastResponse == nil {
            lastResponse = Self.legacyResponse(
                text: try container.decodeIfPresent(String.self, forKey: .lastResponseText),
                at: try container.decodeIfPresent(Date.self, forKey: .lastResponseAt)
            )
        }
        consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        if let failure = try container.decodeIfPresent(
            MonitoringError.self,
            forKey: .lastFailure
        ) {
            lastError = failure
        } else if let legacyMessage = try container.decodeIfPresent(
            String.self,
            forKey: .lastError
        ) {
            lastError = .legacy(legacyMessage)
        } else {
            lastError = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastValue, forKey: .lastValue)
        try container.encodeIfPresent(lastSuccessAt, forKey: .lastSuccessAt)
        try container.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encodeIfPresent(lastResponse, forKey: .lastResponse)
        try container.encode(consecutiveFailures, forKey: .consecutiveFailures)
        try container.encodeIfPresent(lastError, forKey: .lastFailure)
    }
}

public struct Monitor: Identifiable, Codable, Equatable, Sendable {
    public static let minimumRefreshInterval: TimeInterval = 30
    public static let maximumRefreshInterval: TimeInterval = 365 * 24 * 60 * 60
    public static let valuePlaceholder = "${value}"

    public var id: UUID
    public var name: String
    public var urlString: String
    public var requestHeaders: [RequestHeader]
    public var parser: ParserConfiguration
    public var displayTemplate: String
    public var refreshInterval: TimeInterval
    public var refreshIntervalUnit: RefreshIntervalUnit
    public var isEnabled: Bool
    public var showsInMenuBar: Bool
    public var order: Int
    public var runtime: MonitorRuntimeState

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String = "https://",
        requestHeaders: [RequestHeader] = [],
        parser: ParserConfiguration = .init(),
        displayTemplate: String? = nil,
        label: String = "",
        unit: String = "",
        refreshInterval: TimeInterval = 60,
        refreshIntervalUnit: RefreshIntervalUnit = .seconds,
        isEnabled: Bool = true,
        showsInMenuBar: Bool = false,
        order: Int = 0,
        runtime: MonitorRuntimeState = .init()
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.requestHeaders = requestHeaders
        self.parser = parser
        self.displayTemplate = displayTemplate ?? "\(label)\(Self.valuePlaceholder)\(unit)"
        self.refreshInterval = Self.normalizedRefreshInterval(refreshInterval)
        self.refreshIntervalUnit = refreshIntervalUnit
        self.isEnabled = isEnabled
        self.showsInMenuBar = showsInMenuBar
        self.order = order
        self.runtime = runtime
    }

    public var displayedNumber: String {
        guard let value = runtime.displayValue else { return "--" }
        return NumberDisplayFormatter.string(from: value)
    }

    public var displayText: String {
        displayTemplate.replacingOccurrences(
            of: Self.valuePlaceholder,
            with: displayedNumber
        )
    }

    // Compatibility bridge for persisted pre-template settings and the retired editor.
    public var label: String {
        get {
            guard let range = displayTemplate.range(of: Self.valuePlaceholder) else {
                return displayTemplate
            }
            return String(displayTemplate[..<range.lowerBound])
        }
        set {
            displayTemplate = "\(newValue)\(Self.valuePlaceholder)\(unit)"
        }
    }

    // Compatibility bridge for persisted pre-template settings and the retired editor.
    public var unit: String {
        get {
            guard let range = displayTemplate.range(of: Self.valuePlaceholder) else { return "" }
            return String(displayTemplate[range.upperBound...])
        }
        set {
            displayTemplate = "\(label)\(Self.valuePlaceholder)\(newValue)"
        }
    }

    public var menuBarTitle: String {
        displayText
    }

    public static func draft(order: Int) -> Monitor {
        Monitor(name: L10n.string("monitor.default_name"), order: order)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlString
        case requestHeaders
        case parser
        case displayTemplate
        case label
        case unit
        case refreshInterval
        case refreshIntervalUnit
        case isEnabled
        case showsInMenuBar
        case order
        case runtime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlString = try container.decode(String.self, forKey: .urlString)
        requestHeaders = try container.decodeIfPresent([RequestHeader].self, forKey: .requestHeaders) ?? []
        parser = try container.decode(ParserConfiguration.self, forKey: .parser)
        if let storedTemplate = try container.decodeIfPresent(String.self, forKey: .displayTemplate) {
            displayTemplate = storedTemplate
        } else {
            let legacyLabel = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            let legacyUnit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
            displayTemplate = "\(legacyLabel)\(Self.valuePlaceholder)\(legacyUnit)"
        }
        refreshInterval = Self.normalizedRefreshInterval(
            try container.decode(TimeInterval.self, forKey: .refreshInterval)
        )
        refreshIntervalUnit = try container.decodeIfPresent(
            RefreshIntervalUnit.self,
            forKey: .refreshIntervalUnit
        ) ?? .seconds
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        showsInMenuBar = try container.decode(Bool.self, forKey: .showsInMenuBar)
        order = try container.decode(Int.self, forKey: .order)
        runtime = try container.decode(MonitorRuntimeState.self, forKey: .runtime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(requestHeaders, forKey: .requestHeaders)
        try container.encode(parser, forKey: .parser)
        try container.encode(displayTemplate, forKey: .displayTemplate)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(refreshIntervalUnit, forKey: .refreshIntervalUnit)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(showsInMenuBar, forKey: .showsInMenuBar)
        try container.encode(order, forKey: .order)
        try container.encode(runtime, forKey: .runtime)
    }

    public static func normalizedRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return minimumRefreshInterval }
        return min(max(minimumRefreshInterval, interval), maximumRefreshInterval)
    }
}

public struct StoredState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var monitors: [Monitor]

    public init(schemaVersion: Int = 1, monitors: [Monitor]) {
        self.schemaVersion = schemaVersion
        self.monitors = monitors
    }
}
