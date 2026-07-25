import Foundation

public enum MonitoringError: Error, LocalizedError, Codable, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case invalidRequestHeader(String)
    case requestHeaderNameEmpty
    case requestHeaderDuplicate(String)
    case invalidHTTPResponse
    case httpStatus(Int)
    case responseTooLarge
    case unsupportedResponseBody
    case responseBodyNotJSON
    case invalidJSON(String)
    case invalidJSONPath(String)
    case jsonPathRootRequired
    case jsonPathPropertyRequired
    case jsonPathClosingBracketRequired
    case jsonPathInvalidArrayIndex
    case jsonPathInvalidAccess
    case valueNotFound
    case resultIsNotNumber
    case nonFiniteNumber
    case script(String)
    case scriptRuntimeUnavailable
    case scriptUnknownException
    case scriptNoResult
    case scriptServiceUnavailable
    case scriptExecutionFailed
    case scriptTimeout
    case request(String)
    case legacy(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.string("error.invalid_url")
        case .insecureURL: L10n.string("error.https_only")
        case let .invalidRequestHeader(message):
            L10n.format("error.invalid_header", message)
        case .requestHeaderNameEmpty:
            L10n.format("error.invalid_header", L10n.string("error.header_name_required"))
        case let .requestHeaderDuplicate(name):
            L10n.format("error.invalid_header", L10n.format("error.header_duplicate", name))
        case .invalidHTTPResponse: L10n.string("error.invalid_response")
        case let .httpStatus(code): L10n.format("error.http_status", Int64(code))
        case .responseTooLarge: L10n.string("error.response_too_large")
        case .unsupportedResponseBody: L10n.string("error.unsupported_body")
        case .responseBodyNotJSON: L10n.string("error.json_response_required")
        case let .invalidJSON(message): L10n.format("error.invalid_json", message)
        case let .invalidJSONPath(message): L10n.format("error.invalid_json_path", message)
        case .jsonPathRootRequired:
            L10n.format("error.invalid_json_path", L10n.string("error.jsonpath_root_required"))
        case .jsonPathPropertyRequired:
            L10n.format("error.invalid_json_path", L10n.string("error.jsonpath_property_required"))
        case .jsonPathClosingBracketRequired:
            L10n.format("error.invalid_json_path", L10n.string("error.jsonpath_bracket_required"))
        case .jsonPathInvalidArrayIndex:
            L10n.format("error.invalid_json_path", L10n.string("error.jsonpath_index_invalid"))
        case .jsonPathInvalidAccess:
            L10n.format("error.invalid_json_path", L10n.string("error.jsonpath_access_invalid"))
        case .valueNotFound: L10n.string("error.value_not_found")
        case .resultIsNotNumber: L10n.string("error.result_not_number")
        case .nonFiniteNumber: L10n.string("error.non_finite_number")
        case let .script(message): L10n.format("error.script", message)
        case .scriptRuntimeUnavailable:
            L10n.format("error.script", L10n.string("error.script_runtime_unavailable"))
        case .scriptUnknownException:
            L10n.format("error.script", L10n.string("error.script_unknown_exception"))
        case .scriptNoResult:
            L10n.format("error.script", L10n.string("error.script_no_result"))
        case .scriptServiceUnavailable:
            L10n.format("error.script", L10n.string("error.script_service_unavailable"))
        case .scriptExecutionFailed:
            L10n.format("error.script", L10n.string("error.script_execution_failed"))
        case .scriptTimeout: L10n.string("error.script_timeout")
        case let .request(message): L10n.format("error.request", message)
        case let .legacy(message): message
        }
    }
}
