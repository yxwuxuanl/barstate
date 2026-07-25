import Foundation

public enum ResponseBodyKind: String, Codable, Equatable, Sendable {
    case json
    case text
    case binary

    public var javaScriptParameterType: String {
        switch self {
        case .json: "Object"
        case .text: "string"
        case .binary: "Object|string"
        }
    }
}

public struct HTTPResponseHeader: Codable, Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct HTTPResponseSnapshot: Codable, Equatable, Sendable {
    public var requestedAt: Date
    public var statusCode: Int?
    public var reasonPhrase: String?
    public var httpVersion: String?
    public var headers: [HTTPResponseHeader]
    public var bodyText: String
    public var bodyKind: ResponseBodyKind

    public init(
        requestedAt: Date,
        statusCode: Int? = nil,
        reasonPhrase: String? = nil,
        httpVersion: String? = nil,
        headers: [HTTPResponseHeader] = [],
        bodyText: String,
        bodyKind: ResponseBodyKind
    ) {
        self.requestedAt = requestedAt
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.httpVersion = httpVersion
        self.headers = headers
        self.bodyText = bodyText
        self.bodyKind = bodyKind
    }

    public var contentType: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    public var statusText: String? {
        guard let statusCode else { return nil }
        guard let reasonPhrase, !reasonPhrase.isEmpty else { return String(statusCode) }
        return "\(statusCode) \(reasonPhrase)"
    }

    public var statusLine: String? {
        guard let statusText else { return nil }
        return "\(httpVersion ?? "HTTP") \(statusText)"
    }

    public var detailsSummary: String {
        let version = httpVersion ?? "HTTP"
        let key = switch headers.count {
        case 0: "http.details_summary.zero"
        case 1: "http.details_summary.one"
        default: "http.details_summary.other"
        }
        return L10n.format(key, version, Int64(headers.count))
    }

    public var fullHTTPDetails: String {
        var lines: [String] = []
        if let statusLine {
            lines.append(statusLine)
        }
        lines.append(contentsOf: headers.map { "\($0.name): \($0.value)" })
        return lines.isEmpty
            ? L10n.string("http.no_details")
            : lines.joined(separator: "\n")
    }

    public var bodyData: Data {
        Data(bodyText.utf8)
    }
}
