import Foundation
import Testing
@testable import BarStateCore

struct RequestHeaderTests {
    @Test func validatesHeaderNamesAndValues() {
        #expect(RequestHeader(name: "Authorization", value: "Bearer token").isValid)
        #expect(RequestHeader(name: "X-API-Key", value: "secret").isValid)
        #expect(!RequestHeader(name: "Bad Header", value: "value").isValid)
        #expect(!RequestHeader(name: "X-Test", value: "first\nsecond").isValid)
    }

    @Test func identifiesCommonSensitiveHeaderValues() {
        #expect(RequestHeader(name: "Authorization").hasSensitiveValue)
        #expect(RequestHeader(name: " authorization ").hasSensitiveValue)
        #expect(RequestHeader(name: "X-API-Key").hasSensitiveValue)
        #expect(RequestHeader(name: "Cookie").hasSensitiveValue)
        #expect(!RequestHeader(name: "Accept").hasSensitiveValue)
        #expect(!RequestHeader(name: "X-Request-Time").hasSensitiveValue)
    }

    @Test func decodesLegacyMonitorWithoutHeaders() throws {
        let original = Monitor(name: "旧监控项")
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "requestHeaders")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)
        #expect(decoded.requestHeaders.isEmpty)
    }

    @Test func decodesLegacyMonitorWithoutRefreshIntervalUnit() throws {
        let original = Monitor(name: "旧监控项", refreshInterval: 90)
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "refreshIntervalUnit")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)
        #expect(decoded.refreshInterval == 90)
        #expect(decoded.refreshIntervalUnit == .seconds)
    }

    @Test func decodesLegacyRuntimeWithoutResponseFields() throws {
        let original = Monitor(name: "旧监控项")
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var runtime = try #require(object["runtime"] as? [String: Any])
        runtime.removeValue(forKey: "lastResponseText")
        runtime.removeValue(forKey: "lastResponseAt")
        object["runtime"] = runtime
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Monitor.self, from: legacyData)
        #expect(decoded.runtime.lastResponseText == nil)
        #expect(decoded.runtime.lastResponseAt == nil)
    }

    @Test func buildsGETRequestWithCustomHeaders() throws {
        let monitor = Monitor(
            name: "认证接口",
            urlString: "https://api.example.com/value",
            requestHeaders: [
                RequestHeader(name: "Authorization", value: "Bearer token"),
                RequestHeader(name: "X-API-Key", value: "secret")
            ]
        )

        let request = try HTTPRequestBuilder.makeRequest(for: monitor)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "secret")
    }

    @Test func rejectsDuplicateHeaderNamesIgnoringCase() {
        let monitor = Monitor(
            name: "重复 Header",
            urlString: "https://api.example.com/value",
            requestHeaders: [
                RequestHeader(name: "Authorization", value: "one"),
                RequestHeader(name: "authorization", value: "two")
            ]
        )

        #expect(throws: MonitoringError.self) {
            try HTTPRequestBuilder.makeRequest(for: monitor)
        }
    }

    @Test func resolvesTimestampInURLAndRequestHeaders() throws {
        let requestDate = Date(timeIntervalSince1970: 1_720_000_000.987)
        let monitor = Monitor(
            name: "时间戳接口",
            urlString: "https://api.example.com/${TIMESTAMP}?requestedAt=${TIMESTAMP}",
            requestHeaders: [
                RequestHeader(name: "X-Time-${TIMESTAMP}", value: "Bearer ${TIMESTAMP}")
            ]
        )

        let request = try HTTPRequestBuilder.makeRequest(for: monitor, at: requestDate)

        #expect(request.url?.absoluteString == "https://api.example.com/1720000000?requestedAt=1720000000")
        #expect(request.value(forHTTPHeaderField: "X-Time-1720000000") == "Bearer 1720000000")
        #expect(monitor.urlString.contains("${TIMESTAMP}"))
        #expect(monitor.requestHeaders[0].value == "Bearer ${TIMESTAMP}")
    }
}
