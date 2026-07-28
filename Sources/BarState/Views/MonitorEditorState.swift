import BarStateCore
import SwiftUI

struct EditorRequestConfiguration: Equatable {
    let sourceKind: MonitorSourceKind
    let urlString: String
    let promQL: String
    let authentication: HTTPAuthentication
    let requestHeaders: [RequestHeader]
    let requestTimeout: TimeInterval

    init(monitor: Monitor) {
        sourceKind = monitor.sourceKind
        urlString = monitor.urlString
        promQL = monitor.sourceKind == .prometheus ? monitor.promQL : ""
        authentication = monitor.authentication
        requestHeaders = monitor.requestHeaders
        requestTimeout = monitor.requestTimeout
    }
}
struct EditorTestConfiguration: Equatable {
    let request: EditorRequestConfiguration
    let parser: ParserConfiguration?

    init(monitor: Monitor) {
        request = EditorRequestConfiguration(monitor: monitor)
        parser = monitor.sourceKind == .httpAPI ? monitor.parser : nil
    }
}
struct EditorRequestFailure: Equatable {
    let message: String
    let attemptedAt: Date
    let requestDuration: TimeInterval?
}

enum RequestHeaderLayoutMetrics {
    static let columnSpacing: CGFloat = 10
    static let actionSize: CGFloat = 28
    static let actionsWidth = actionSize * 2 + columnSpacing
}

func stableRequestHeaderBinding(
    for header: RequestHeader,
    in headers: Binding<[RequestHeader]>
) -> Binding<RequestHeader> {
    Binding(
        get: {
            headers.wrappedValue.first { $0.id == header.id } ?? header
        },
        set: { updatedHeader in
            var currentHeaders = headers.wrappedValue
            guard let index = currentHeaders.firstIndex(where: { $0.id == header.id }) else {
                return
            }
            var updatedHeader = updatedHeader
            updatedHeader.id = header.id
            currentHeaders[index] = updatedHeader
            headers.wrappedValue = currentHeaders
        }
    )
}

enum EditorFormLayoutMetrics {
    static let labelWidth: CGFloat = 128
}

struct EditorEditableConfiguration: Equatable {
    let name: String
    let sourceKind: MonitorSourceKind
    let urlString: String
    let promQL: String
    let authentication: HTTPAuthentication
    let requestHeaders: [RequestHeader]
    let parser: ParserConfiguration
    let displayTemplate: String
    let refreshInterval: TimeInterval
    let refreshIntervalUnit: RefreshIntervalUnit
    let requestTimeout: TimeInterval

    init(monitor: Monitor) {
        name = monitor.name
        sourceKind = monitor.sourceKind
        urlString = monitor.urlString
        promQL = monitor.promQL
        authentication = monitor.authentication
        requestHeaders = monitor.requestHeaders
        parser = monitor.parser
        displayTemplate = monitor.displayTemplate
        refreshInterval = monitor.refreshInterval
        refreshIntervalUnit = monitor.refreshIntervalUnit
        requestTimeout = monitor.requestTimeout
    }
}
