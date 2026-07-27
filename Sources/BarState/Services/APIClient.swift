import BarStateCore
import Foundation

struct RequestOutcome: Sendable {
    let response: HTTPResponseSnapshot?
    let requestedAt: Date
    let requestDuration: TimeInterval
    let error: MonitoringError?
}

struct DryRunOutcome: Sendable {
    let formattedResponse: String?
    let result: Result<Double, MonitoringError>
}

struct FetchOutcome: Sendable {
    let response: HTTPResponseSnapshot?
    let requestedAt: Date
    let requestDuration: TimeInterval?
    let result: Result<Double, MonitoringError>

    var formattedResponse: String? { response?.bodyText }

    init(
        response: HTTPResponseSnapshot?,
        requestedAt: Date,
        requestDuration: TimeInterval? = nil,
        result: Result<Double, MonitoringError>
    ) {
        self.response = response
        self.requestedAt = requestedAt
        self.requestDuration = requestDuration ?? response?.requestDuration
        self.result = result
    }

    init(
        formattedResponse: String?,
        requestedAt: Date,
        requestDuration: TimeInterval? = nil,
        result: Result<Double, MonitoringError>
    ) {
        self.requestedAt = requestedAt
        self.requestDuration = requestDuration
        self.result = result
        if let formattedResponse {
            let kind: ResponseBodyKind = (try? JSONSerialization.jsonObject(
                with: Data(formattedResponse.utf8),
                options: [.fragmentsAllowed]
            )) == nil ? .text : .json
            self.response = HTTPResponseSnapshot(
                requestedAt: requestedAt,
                requestDuration: requestDuration,
                bodyText: formattedResponse,
                bodyKind: kind
            )
        } else {
            self.response = nil
        }
    }
}

actor APIClient: MonitorValueFetching {
    private struct HTTPPayload: @unchecked Sendable {
        let data: Data
        let response: HTTPURLResponse
        let protocolName: String?
    }

    private let session: URLSession
    private let scriptService: ScriptServiceClient
    private let maximumResponseSize = 2 * 1_024 * 1_024

    init(scriptService: ScriptServiceClient = ScriptServiceClient()) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = Monitor.maximumRequestTimeout
        configuration.timeoutIntervalForResource = Monitor.maximumRequestTimeout
        self.session = URLSession(configuration: configuration)
        self.scriptService = scriptService
    }

    func fetchValue(for monitor: Monitor) async -> FetchOutcome {
        let requestOutcome = await request(for: monitor)
        guard let response = requestOutcome.response else {
            return FetchOutcome(
                response: nil,
                requestedAt: requestOutcome.requestedAt,
                requestDuration: requestOutcome.requestDuration,
                result: .failure(requestOutcome.error ?? .invalidHTTPResponse)
            )
        }
        if let error = requestOutcome.error {
            return FetchOutcome(
                response: response,
                requestedAt: requestOutcome.requestedAt,
                requestDuration: requestOutcome.requestDuration,
                result: .failure(error)
            )
        }

        return FetchOutcome(
            response: response,
            requestedAt: requestOutcome.requestedAt,
            requestDuration: requestOutcome.requestDuration,
            result: await parseValue(from: response, for: monitor)
        )
    }

    func request(for monitor: Monitor) async -> RequestOutcome {
        let requestedAt = Date()
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let payload = try await fetchPayloadBeforeDeadline(for: monitor)
            let requestDuration = Self.elapsedTime(since: startedAt)
            let response = Self.makeSnapshot(
                from: payload,
                requestedAt: requestedAt,
                requestDuration: requestDuration
            )
            let statusCode = payload.response.statusCode
            let statusError: MonitoringError? = if (200...299).contains(statusCode) {
                nil
            } else if monitor.sourceKind == .prometheus,
                      let prometheusError = PrometheusResponseParser.apiError(from: payload.data)
            {
                prometheusError
            } else {
                .httpStatus(statusCode)
            }
            return RequestOutcome(
                response: response,
                requestedAt: requestedAt,
                requestDuration: requestDuration,
                error: statusError
            )
        } catch let error as URLError where error.code == .timedOut {
            return RequestOutcome(
                response: nil,
                requestedAt: requestedAt,
                requestDuration: Self.elapsedTime(since: startedAt),
                error: .requestTimedOut
            )
        } catch let error as MonitoringError {
            return RequestOutcome(
                response: nil,
                requestedAt: requestedAt,
                requestDuration: Self.elapsedTime(since: startedAt),
                error: error
            )
        } catch {
            return RequestOutcome(
                response: nil,
                requestedAt: requestedAt,
                requestDuration: Self.elapsedTime(since: startedAt),
                error: .request(error.localizedDescription)
            )
        }
    }

    private func fetchPayloadBeforeDeadline(for monitor: Monitor) async throws -> HTTPPayload {
        try await withThrowingTaskGroup(of: HTTPPayload.self) { group in
            group.addTask {
                try await self.fetchPayload(for: monitor)
            }
            group.addTask {
                try await Task<Never, Never>.sleep(
                    for: .seconds(monitor.requestTimeout)
                )
                throw URLError(.timedOut)
            }

            defer { group.cancelAll() }
            guard let payload = try await group.next() else {
                throw MonitoringError.invalidHTTPResponse
            }
            return payload
        }
    }

    func dryRun(for monitor: Monitor) async -> DryRunOutcome {
        let requestOutcome = await request(for: monitor)
        guard let response = requestOutcome.response else {
            return DryRunOutcome(
                formattedResponse: nil,
                result: .failure(requestOutcome.error ?? .invalidHTTPResponse)
            )
        }
        if let error = requestOutcome.error {
            return DryRunOutcome(formattedResponse: response.bodyText, result: .failure(error))
        }
        return DryRunOutcome(
            formattedResponse: response.bodyText,
            result: await parseValue(from: response, for: monitor)
        )
    }

    func parseValue(
        from response: HTTPResponseSnapshot,
        for monitor: Monitor
    ) async -> Result<Double, MonitoringError> {
        do {
            let value: Double
            switch monitor.sourceKind {
            case .prometheus:
                guard response.bodyKind == .json else {
                    throw MonitoringError.responseBodyNotJSON
                }
                value = try PrometheusResponseParser.number(from: response.bodyData)

            case .httpAPI:
                switch monitor.parser.kind {
                case .jsonPath:
                    guard response.bodyKind == .json else {
                        throw MonitoringError.responseBodyNotJSON
                    }
                    let json: Any
                    do {
                        json = try JSONSerialization.jsonObject(
                            with: response.bodyData,
                            options: [.fragmentsAllowed]
                        )
                    } catch {
                        throw MonitoringError.invalidJSON(error.localizedDescription)
                    }
                    value = try JSONPathParser.number(at: monitor.parser.jsonPath, in: json)

                case .javaScript:
                    guard response.bodyKind != .binary else {
                        throw MonitoringError.unsupportedResponseBody
                    }
                    value = try await scriptService.evaluate(
                        responseData: response.bodyData,
                        scriptBody: monitor.parser.scriptBody
                    )
                }
            }

            guard value.isFinite else { throw MonitoringError.nonFiniteNumber }
            return .success(value)
        } catch let error as MonitoringError {
            return .failure(error)
        } catch {
            return .failure(.request(error.localizedDescription))
        }
    }

    private func fetchPayload(for monitor: Monitor) async throws -> HTTPPayload {
        let request = try HTTPRequestBuilder.makeRequest(for: monitor)
        let metricsCollector = TaskMetricsCollector()

        do {
            let (bytes, response) = try await session.bytes(
                for: request,
                delegate: metricsCollector
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                metricsCollector.finishIfNeeded(with: nil)
                throw MonitoringError.invalidHTTPResponse
            }
            if httpResponse.expectedContentLength > maximumResponseSize {
                metricsCollector.finishIfNeeded(with: nil)
                throw MonitoringError.responseTooLarge
            }

            var data = Data()
            if httpResponse.expectedContentLength > 0 {
                data.reserveCapacity(min(Int(httpResponse.expectedContentLength), maximumResponseSize))
            }
            for try await byte in bytes {
                guard data.count < maximumResponseSize else {
                    metricsCollector.finishIfNeeded(with: nil)
                    throw MonitoringError.responseTooLarge
                }
                data.append(byte)
            }

            return HTTPPayload(
                data: data,
                response: httpResponse,
                protocolName: await metricsCollector.collectedProtocolName()
            )
        } catch {
            metricsCollector.finishIfNeeded(with: nil)
            throw error
        }
    }

    nonisolated private static func makeSnapshot(
        from payload: HTTPPayload,
        requestedAt: Date,
        requestDuration: TimeInterval
    ) -> HTTPResponseSnapshot {
        let body = formatBody(
            payload.data,
            textEncodingName: payload.response.textEncodingName
        )
        let headers = payload.response.allHeaderFields
            .map { HTTPResponseHeader(name: String(describing: $0.key), value: String(describing: $0.value)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let statusCode = payload.response.statusCode

        return HTTPResponseSnapshot(
            requestedAt: requestedAt,
            requestDuration: requestDuration,
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            httpVersion: displayProtocolName(payload.protocolName),
            headers: headers,
            bodyText: body.text,
            bodyKind: body.kind
        )
    }

    nonisolated private static func elapsedTime(since uptime: TimeInterval) -> TimeInterval {
        max(0, ProcessInfo.processInfo.systemUptime - uptime)
    }

    nonisolated private static func formatBody(
        _ data: Data,
        textEncodingName: String?
    ) -> (text: String, kind: ResponseBodyKind) {
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(
               withJSONObject: json,
               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
           ),
           let prettyString = String(data: prettyData, encoding: .utf8)
        {
            return (prettyString, .json)
        }

        if let text = decodeText(data, declaredEncodingName: textEncodingName) {
            return (text, .text)
        }
        return (L10n.format("response.binary_body", Int64(data.count)), .binary)
    }

    nonisolated private static func decodeText(
        _ data: Data,
        declaredEncodingName: String?
    ) -> String? {
        var encodings: [String.Encoding] = []
        if let name = declaredEncodingName?.lowercased() {
            let declaredEncoding: String.Encoding? = switch name {
            case "utf-8", "utf8": .utf8
            case "utf-16", "utf16": .utf16
            case "utf-16le": .utf16LittleEndian
            case "utf-16be": .utf16BigEndian
            case "iso-8859-1", "latin1": .isoLatin1
            case "us-ascii", "ascii": .ascii
            case "windows-1252", "cp1252": .windowsCP1252
            default: nil
            }
            if let declaredEncoding {
                encodings.append(declaredEncoding)
            }
        }
        if !encodings.contains(.utf8) {
            encodings.append(.utf8)
        }

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    nonisolated private static func displayProtocolName(_ protocolName: String?) -> String? {
        guard let protocolName, !protocolName.isEmpty else { return nil }
        return switch protocolName.lowercased() {
        case "h2": "HTTP/2"
        case "h3": "HTTP/3"
        case "http/1.0": "HTTP/1.0"
        case "http/1.1": "HTTP/1.1"
        default: protocolName.uppercased()
        }
    }

    nonisolated private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 408: "Request Timeout"
        case 409: "Conflict"
        case 422: "Unprocessable Content"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
        }
    }
}

private final class TaskMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var protocolName: String?
    private var isFinished = false
    private var continuation: CheckedContinuation<String?, Never>?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        finishIfNeeded(with: metrics.transactionMetrics.last?.networkProtocolName)
    }

    func collectedProtocolName() async -> String? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isFinished {
                let protocolName = self.protocolName
                lock.unlock()
                continuation.resume(returning: protocolName)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func finishIfNeeded(with protocolName: String?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        self.protocolName = protocolName
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: protocolName)
    }
}
