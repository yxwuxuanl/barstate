import Foundation

public enum HTTPRequestBuilder {
    public static func makeRequest(
        for monitor: Monitor,
        timeoutInterval: TimeInterval? = nil,
        at date: Date = Date()
    ) throws -> URLRequest {
        let resolvedURLString = RequestTemplateResolver.resolve(monitor.urlString, at: date)
        guard var components = URLComponents(string: resolvedURLString),
              components.host != nil
        else {
            throw MonitoringError.invalidURL
        }
        guard isSupportedEndpoint(
            components,
            allowsLoopbackHTTP: monitor.sourceKind == .prometheus
        ) else {
            throw MonitoringError.insecureURL
        }

        if monitor.sourceKind == .prometheus {
            let query = monitor.promQL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw MonitoringError.prometheusQueryRequired
            }
            components.fragment = nil
            components.path = prometheusQueryPath(from: components.path)
            var queryItems = components.queryItems?.filter { $0.name != "query" } ?? []
            queryItems.append(URLQueryItem(name: "query", value: query))
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MonitoringError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Monitor.normalizedRequestTimeout(
            timeoutInterval ?? monitor.requestTimeout
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if monitor.sourceKind == .prometheus {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        var headerNames: Set<String> = []
        if let authorization = monitor.authentication.authorizationHeaderValue {
            guard !monitor.authentication.username.contains(":") else {
                throw MonitoringError.basicAuthenticationUsernameContainsColon
            }
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            headerNames.insert("authorization")
        }

        for header in monitor.requestHeaders {
            let resolvedHeader = RequestHeader(
                name: RequestTemplateResolver.resolve(header.name, at: date),
                value: RequestTemplateResolver.resolve(header.value, at: date)
            )
            guard resolvedHeader.isValid else {
                if resolvedHeader.name.isEmpty {
                    throw MonitoringError.requestHeaderNameEmpty
                }
                throw MonitoringError.invalidRequestHeader(resolvedHeader.name)
            }

            let normalizedName = resolvedHeader.normalizedName
            if normalizedName.caseInsensitiveCompare("Authorization") == .orderedSame,
               monitor.authentication.kind == .basic
            {
                throw MonitoringError.authorizationHeaderConflict
            }
            guard headerNames.insert(normalizedName.lowercased()).inserted else {
                throw MonitoringError.requestHeaderDuplicate(normalizedName)
            }
            request.setValue(resolvedHeader.value, forHTTPHeaderField: normalizedName)
        }

        return request
    }

    public static func isSupportedEndpoint(
        _ components: URLComponents,
        allowsLoopbackHTTP: Bool = false
    ) -> Bool {
        guard components.host != nil else { return false }
        return switch components.scheme?.lowercased() {
        case "https":
            true
        case "http":
            allowsLoopbackHTTP && isLoopbackHost(components.host)
        default:
            false
        }
    }

    private static func prometheusQueryPath(from basePath: String) -> String {
        let normalized = basePath == "/"
            ? ""
            : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("api/v1/query") {
            return "/\(normalized)"
        }
        return normalized.isEmpty
            ? "/api/v1/query"
            : "/\(normalized)/api/v1/query"
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ UInt8($0) != nil })
        else { return false }
        return octets[0] == "127"
    }
}
