import Foundation
import Testing
@testable import BarStateCore

struct PrometheusTemplateTests {
    @Test func requiresAnUnambiguousTarget() {
        #expect(throws: MonitoringError.prometheusTargetRequired) {
            try PrometheusTemplate().query()
        }
    }

    @Test func targetLabelsCannotInjectPromQL() throws {
        let template = PrometheusTemplate(kind: .targetUp, job: "node", instance: "host\"} or up #")
        #expect(try template.query() == #"up{job="node",instance="host\"} or up #"}"#)
    }

    @Test func diskTemplateSelectsMountAndRejectsZeroSizedFilesystems() throws {
        let query = try PrometheusTemplate(kind: .disk, instance: "host:9100", mountPoint: "/data").query()
        #expect(query.contains(#"mountpoint="/data""#))
        #expect(query.contains("node_filesystem_avail_bytes"))
        #expect(query.contains("and (node_filesystem_size_bytes"))
        #expect(query.hasSuffix(" > 0)"))
    }

    @Test func templateQueryIsUsedByRequestBuilder() throws {
        let monitor = Monitor(
            name: "CPU", sourceKind: .prometheus,
            prometheusTemplate: PrometheusTemplate(kind: .cpu, instance: "host:9100"),
            urlString: "http://localhost:9090", promQL: "ignored"
        )
        let request = try HTTPRequestBuilder.makeRequest(for: monitor)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v1/query")
        let expectedQuery = try monitor.prometheusTemplate?.query()
        #expect(components.queryItems?.first { $0.name == "query" }?.value == expectedQuery)
    }

    @Test func targetDownRemainsAValidZeroSample() throws {
        let data = Data(#"{"status":"success","data":{"resultType":"vector","result":[{"metric":{"job":"node","instance":"host:9100"},"value":[1700000000,"0"]}]}}"#.utf8)
        #expect(try PrometheusResponseParser.number(from: data) == 0)
    }
}
