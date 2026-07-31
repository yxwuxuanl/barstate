import Foundation

public enum MonitorSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case httpAPI
    case prometheus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .httpAPI: "HTTP API"
        case .prometheus: "Prometheus"
        }
    }
}

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

public enum HTTPAuthenticationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case basic

    public var id: String { rawValue }
}

public struct HTTPAuthentication: Codable, Equatable, Sendable {
    public var kind: HTTPAuthenticationKind
    public var username: String
    public var password: String

    public init(
        kind: HTTPAuthenticationKind = .none,
        username: String = "",
        password: String = ""
    ) {
        self.kind = kind
        self.username = username
        self.password = password
    }

    public var authorizationHeaderValue: String? {
        guard kind == .basic else { return nil }
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(credentials)"
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

public enum MenuBarPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case individual
    case compact

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .individual: L10n.string("settings.menu_bar_individual")
        case .compact: L10n.string("settings.menu_bar_compact")
        }
    }
}

public enum StatusIndicatorColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case pink
    case gray

    public var id: String { rawValue }
}

public struct StatusIndicatorRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var value: Double
    public var color: StatusIndicatorColor

    public init(
        id: UUID = UUID(),
        value: Double = 0,
        color: StatusIndicatorColor = .green
    ) {
        self.id = id
        self.value = value
        self.color = color
    }
}

public enum StatusIndicatorAppearanceKind: Equatable, Sendable {
    case matched
    case unavailable
    case mixed
}

public struct StatusIndicatorAppearance: Equatable, Sendable {
    public let color: StatusIndicatorColor
    public let kind: StatusIndicatorAppearanceKind

    public init(
        color: StatusIndicatorColor,
        kind: StatusIndicatorAppearanceKind = .matched
    ) {
        self.color = color
        self.kind = kind
    }
}

public struct StatusIndicatorConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var rules: [StatusIndicatorRule]

    public init(
        isEnabled: Bool = false,
        rules: [StatusIndicatorRule] = []
    ) {
        self.isEnabled = isEnabled
        self.rules = rules
    }

    public var hasValidRules: Bool {
        guard !rules.isEmpty, rules.allSatisfy({ $0.value.isFinite }) else { return false }
        return Set(rules.map(\.value)).count == rules.count
    }

    public func appearance(for value: Double?) -> StatusIndicatorAppearance? {
        guard isEnabled else { return nil }
        guard let value, value.isFinite, hasValidRules else {
            return StatusIndicatorAppearance(color: .gray, kind: .unavailable)
        }
        guard let rule = rules
            .filter({ value >= $0.value })
            .max(by: { $0.value < $1.value })
        else {
            return StatusIndicatorAppearance(color: .gray, kind: .unavailable)
        }
        return StatusIndicatorAppearance(color: rule.color)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case rules
        // Compatibility with the earlier tier-based status indicator.
        case direction
        case warningThreshold
        case criticalThreshold
        case normalColor
        case warningColor
        case criticalColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        if let rules = try container.decodeIfPresent(
            [StatusIndicatorRule].self,
            forKey: .rules
        ) {
            self.init(isEnabled: isEnabled, rules: rules)
            return
        }

        var migratedRules: [StatusIndicatorRule] = []
        if let warningValue = try container.decodeIfPresent(
            Double.self,
            forKey: .warningThreshold
        ) {
            migratedRules.append(StatusIndicatorRule(
                value: warningValue,
                color: try container.decodeIfPresent(
                    StatusIndicatorColor.self,
                    forKey: .warningColor
                ) ?? .orange
            ))
        }
        if let criticalValue = try container.decodeIfPresent(
            Double.self,
            forKey: .criticalThreshold
        ) {
            migratedRules.append(StatusIndicatorRule(
                value: criticalValue,
                color: try container.decodeIfPresent(
                    StatusIndicatorColor.self,
                    forKey: .criticalColor
                ) ?? .red
            ))
        }
        self.init(isEnabled: isEnabled, rules: migratedRules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(rules, forKey: .rules)
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public static let minimumMenuBarCharacters = 8
    public static let defaultMenuBarCharacters = 24
    public static let maximumMenuBarCharacters = 48

    public var menuBarPresentation: MenuBarPresentation
    public var menuBarMaximumCharacters: Int

    public init(
        menuBarPresentation: MenuBarPresentation = .individual,
        menuBarMaximumCharacters: Int = AppPreferences.defaultMenuBarCharacters
    ) {
        self.menuBarPresentation = menuBarPresentation
        self.menuBarMaximumCharacters = Self.normalizedMenuBarCharacters(
            menuBarMaximumCharacters
        )
    }

    public static func normalizedMenuBarCharacters(_ value: Int) -> Int {
        min(max(value, minimumMenuBarCharacters), maximumMenuBarCharacters)
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarPresentation
        case menuBarMaximumCharacters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            menuBarPresentation: try container.decodeIfPresent(
                MenuBarPresentation.self,
                forKey: .menuBarPresentation
            ) ?? .individual,
            menuBarMaximumCharacters: try container.decodeIfPresent(
                Int.self,
                forKey: .menuBarMaximumCharacters
            ) ?? Self.defaultMenuBarCharacters
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(menuBarPresentation, forKey: .menuBarPresentation)
        try container.encode(menuBarMaximumCharacters, forKey: .menuBarMaximumCharacters)
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
    public var lastRequestDuration: TimeInterval?
    public var lastResponse: HTTPResponseSnapshot?
    public var consecutiveFailures: Int
    public var lastError: MonitoringError?

    public init(
        lastValue: Double? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastRequestDuration: TimeInterval? = nil,
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
        self.lastRequestDuration = Self.normalizedDuration(
            lastRequestDuration ?? self.lastResponse?.requestDuration
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
        responseAt: Date? = nil,
        requestDuration: TimeInterval? = nil
    ) {
        lastValue = value
        lastSuccessAt = date
        lastAttemptAt = date
        consecutiveFailures = 0
        lastError = nil
        lastRequestDuration = Self.normalizedDuration(
            requestDuration ?? response?.requestDuration
        )
        recordResponse(response, legacyText: responseText, at: responseAt)
    }

    public mutating func recordFailure(
        _ error: MonitoringError,
        at date: Date,
        response: HTTPResponseSnapshot? = nil,
        responseText: String? = nil,
        responseAt: Date? = nil,
        requestDuration: TimeInterval? = nil
    ) {
        lastAttemptAt = date
        consecutiveFailures += 1
        lastError = error
        lastRequestDuration = Self.normalizedDuration(
            requestDuration ?? response?.requestDuration
        )
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

    private static func normalizedDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    private enum CodingKeys: String, CodingKey {
        case lastValue
        case lastSuccessAt
        case lastAttemptAt
        case lastRequestDuration
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
        lastRequestDuration = Self.normalizedDuration(
            try container.decodeIfPresent(TimeInterval.self, forKey: .lastRequestDuration)
                ?? lastResponse?.requestDuration
        )
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
        try container.encodeIfPresent(lastRequestDuration, forKey: .lastRequestDuration)
        try container.encodeIfPresent(lastResponse, forKey: .lastResponse)
        try container.encode(consecutiveFailures, forKey: .consecutiveFailures)
        try container.encodeIfPresent(lastError, forKey: .lastFailure)
    }
}

public struct Monitor: Identifiable, Codable, Equatable, Sendable {
    public static let minimumRefreshInterval: TimeInterval = 30
    public static let maximumRefreshInterval: TimeInterval = 365 * 24 * 60 * 60
    public static let minimumRequestTimeout: TimeInterval = 1
    public static let defaultRequestTimeout: TimeInterval = 10
    public static let maximumRequestTimeout: TimeInterval = 60
    public static let valuePlaceholder = "${value}"

    public var id: UUID
    public var name: String
    public var sourceKind: MonitorSourceKind
    public var urlString: String
    public var promQL: String
    public var authentication: HTTPAuthentication
    public var requestHeaders: [RequestHeader]
    public var parser: ParserConfiguration
    public var displayTemplate: String
    public var statusIndicator: StatusIndicatorConfiguration
    public var refreshInterval: TimeInterval
    public var refreshIntervalUnit: RefreshIntervalUnit
    public var requestTimeout: TimeInterval
    public var isEnabled: Bool
    public var showsInMenuBar: Bool
    public var order: Int
    public var runtime: MonitorRuntimeState

    public init(
        id: UUID = UUID(),
        name: String,
        sourceKind: MonitorSourceKind = .httpAPI,
        urlString: String = "https://",
        promQL: String = "",
        authentication: HTTPAuthentication = .init(),
        requestHeaders: [RequestHeader] = [],
        parser: ParserConfiguration = .init(),
        displayTemplate: String? = nil,
        statusIndicator: StatusIndicatorConfiguration = .init(),
        label: String = "",
        unit: String = "",
        refreshInterval: TimeInterval = 60,
        refreshIntervalUnit: RefreshIntervalUnit = .seconds,
        requestTimeout: TimeInterval = Monitor.defaultRequestTimeout,
        isEnabled: Bool = true,
        showsInMenuBar: Bool = false,
        order: Int = 0,
        runtime: MonitorRuntimeState = .init()
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.urlString = urlString
        self.promQL = promQL
        self.authentication = authentication
        self.requestHeaders = requestHeaders
        self.parser = parser
        self.displayTemplate = displayTemplate ?? "\(label)\(Self.valuePlaceholder)\(unit)"
        self.statusIndicator = statusIndicator
        self.refreshInterval = Self.normalizedRefreshInterval(refreshInterval)
        self.refreshIntervalUnit = refreshIntervalUnit
        self.requestTimeout = Self.normalizedRequestTimeout(requestTimeout)
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

    public var statusIndicatorAppearance: StatusIndicatorAppearance? {
        statusIndicator.appearance(for: runtime.displayValue)
    }

    public static func draft(order: Int) -> Monitor {
        Monitor(name: L10n.string("monitor.default_name"), order: order)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceKind
        case urlString
        case promQL
        case authentication
        case requestHeaders
        case parser
        case displayTemplate
        case statusIndicator
        case label
        case unit
        case refreshInterval
        case refreshIntervalUnit
        case requestTimeout
        case isEnabled
        case showsInMenuBar
        case order
        case runtime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceKind = try container.decodeIfPresent(
            MonitorSourceKind.self,
            forKey: .sourceKind
        ) ?? .httpAPI
        urlString = try container.decode(String.self, forKey: .urlString)
        promQL = try container.decodeIfPresent(String.self, forKey: .promQL) ?? ""
        authentication = try container.decodeIfPresent(
            HTTPAuthentication.self,
            forKey: .authentication
        ) ?? .init()
        requestHeaders = try container.decodeIfPresent([RequestHeader].self, forKey: .requestHeaders) ?? []
        parser = try container.decode(ParserConfiguration.self, forKey: .parser)
        if let storedTemplate = try container.decodeIfPresent(String.self, forKey: .displayTemplate) {
            displayTemplate = storedTemplate
        } else {
            let legacyLabel = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            let legacyUnit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
            displayTemplate = "\(legacyLabel)\(Self.valuePlaceholder)\(legacyUnit)"
        }
        statusIndicator = try container.decodeIfPresent(
            StatusIndicatorConfiguration.self,
            forKey: .statusIndicator
        ) ?? .init()
        refreshInterval = Self.normalizedRefreshInterval(
            try container.decode(TimeInterval.self, forKey: .refreshInterval)
        )
        refreshIntervalUnit = try container.decodeIfPresent(
            RefreshIntervalUnit.self,
            forKey: .refreshIntervalUnit
        ) ?? .seconds
        requestTimeout = Self.normalizedRequestTimeout(
            try container.decodeIfPresent(TimeInterval.self, forKey: .requestTimeout)
                ?? Self.defaultRequestTimeout
        )
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        showsInMenuBar = try container.decode(Bool.self, forKey: .showsInMenuBar)
        order = try container.decode(Int.self, forKey: .order)
        runtime = try container.decode(MonitorRuntimeState.self, forKey: .runtime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(promQL, forKey: .promQL)
        try container.encode(authentication, forKey: .authentication)
        try container.encode(requestHeaders, forKey: .requestHeaders)
        try container.encode(parser, forKey: .parser)
        try container.encode(displayTemplate, forKey: .displayTemplate)
        try container.encode(statusIndicator, forKey: .statusIndicator)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(refreshIntervalUnit, forKey: .refreshIntervalUnit)
        try container.encode(requestTimeout, forKey: .requestTimeout)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(showsInMenuBar, forKey: .showsInMenuBar)
        try container.encode(order, forKey: .order)
        try container.encode(runtime, forKey: .runtime)
    }

    public static func normalizedRefreshInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return minimumRefreshInterval }
        return min(max(minimumRefreshInterval, interval), maximumRefreshInterval)
    }

    public static func normalizedRequestTimeout(_ timeout: TimeInterval) -> TimeInterval {
        guard timeout.isFinite else { return defaultRequestTimeout }
        return min(max(minimumRequestTimeout, timeout), maximumRequestTimeout)
    }
}

public struct StoredState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var monitors: [Monitor]
    public var preferences: AppPreferences

    public init(
        schemaVersion: Int = 1,
        monitors: [Monitor],
        preferences: AppPreferences = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.monitors = monitors
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case monitors
        case preferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        monitors = try container.decode([Monitor].self, forKey: .monitors)
        preferences = try container.decodeIfPresent(
            AppPreferences.self,
            forKey: .preferences
        ) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(monitors, forKey: .monitors)
        try container.encode(preferences, forKey: .preferences)
    }
}
