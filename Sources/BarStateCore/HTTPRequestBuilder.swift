import Foundation

public enum HTTPRequestBuilder {
    public static func makeRequest(
        for monitor: Monitor,
        timeoutInterval: TimeInterval = 10,
        at date: Date = Date()
    ) throws -> URLRequest {
        let resolvedURLString = RequestTemplateResolver.resolve(monitor.urlString, at: date)
        guard let url = URL(string: resolvedURLString), url.host != nil else {
            throw MonitoringError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw MonitoringError.insecureURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var headerNames: Set<String> = []
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
            guard headerNames.insert(normalizedName.lowercased()).inserted else {
                throw MonitoringError.requestHeaderDuplicate(normalizedName)
            }
            request.setValue(resolvedHeader.value, forHTTPHeaderField: normalizedName)
        }

        return request
    }
}
