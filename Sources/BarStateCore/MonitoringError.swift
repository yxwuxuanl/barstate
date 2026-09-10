import Foundation

public enum MonitoringError: Error, LocalizedError, Codable, Equatable, Sendable {
    case invalidURL
    case insecureURL
    case invalidRequestHeader(String)
    case requestHeaderNameEmpty
    case requestHeaderDuplicate(String)
    case basicAuthenticationUsernameContainsColon
    case authorizationHeaderConflict
    case invalidHTTPResponse
    case requestTimedOut
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
    case prometheusQueryFailed(String, String)
    case prometheusQueryRequired
    case prometheusEmptyResult
    case prometheusMultipleSeries(Int)
    case prometheusUnsupportedResultType(String)
    case prometheusMissingValue
    case prometheusTargetRequired
    case prometheusMountRequired
    case codexAuthFileNotFound
    case codexAuthFileUnreadable
    case codexAccessTokenMissing
    case codexQuotaMissing
    case codexQuotaInvalid
    case presetKeyRequired
    case presetKeyInvalid
    case presetMetricUnsupported
    case presetCurrencyUnavailable
    case presetBudgetUnset
    case presetServiceRejected
    case presetValueMissing
    case presetInvalidData
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
        case .basicAuthenticationUsernameContainsColon:
            L10n.string("error.basic_auth_username_colon")
        case .authorizationHeaderConflict:
            L10n.string("error.authorization_header_conflict")
        case .invalidHTTPResponse: L10n.string("error.invalid_response")
        case .requestTimedOut: L10n.string("error.request_timed_out")
        case .httpStatus(401): L10n.string("error.http_unauthorized")
        case .httpStatus(403): L10n.string("error.http_forbidden")
        case .httpStatus(429): L10n.string("error.http_rate_limited")
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
        case let .prometheusQueryFailed(errorType, message):
            L10n.format("error.prometheus_query_failed", errorType, message)
        case .prometheusQueryRequired:
            L10n.string("error.prometheus_query_required")
        case .prometheusEmptyResult:
            L10n.string("error.prometheus_empty_result")
        case let .prometheusMultipleSeries(count):
            L10n.format("error.prometheus_multiple_series", Int64(count))
        case let .prometheusUnsupportedResultType(resultType):
            L10n.format("error.prometheus_unsupported_result_type", resultType)
        case .prometheusMissingValue:
            L10n.string("error.prometheus_missing_value")
        case .prometheusTargetRequired: L10n.string("error.prometheus_target_required")
        case .prometheusMountRequired: L10n.string("error.prometheus_mount_required")
        case .codexAuthFileNotFound:
            L10n.string("error.codex_auth_file_not_found")
        case .codexAuthFileUnreadable:
            L10n.string("error.codex_auth_file_unreadable")
        case .codexAccessTokenMissing:
            L10n.string("error.codex_access_token_missing")
        case .codexQuotaMissing:
            L10n.string("error.codex_quota_missing")
        case .codexQuotaInvalid:
            L10n.string("error.codex_quota_invalid")
        case .presetKeyRequired: L10n.string("error.preset_key_required")
        case .presetKeyInvalid: L10n.string("error.preset_key_invalid")
        case .presetMetricUnsupported: L10n.string("error.preset_metric_unsupported")
        case .presetCurrencyUnavailable: L10n.string("error.preset_currency_unavailable")
        case .presetBudgetUnset: L10n.string("error.preset_budget_unset")
        case .presetServiceRejected: L10n.string("error.preset_service_rejected")
        case .presetValueMissing: L10n.string("error.preset_value_missing")
        case .presetInvalidData: L10n.string("error.preset_invalid_data")
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
