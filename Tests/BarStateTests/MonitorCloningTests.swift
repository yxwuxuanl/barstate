import BarStateCore
import Foundation
import Testing
@testable import BarState

struct MonitorCloningTests {
    @Test func cloneCopiesConfigurationWithFreshIdentityAndRuntime() throws {
        var runtime = MonitorRuntimeState()
        runtime.recordSuccess(42, at: Date(timeIntervalSince1970: 1_234))
        let source = Monitor(
            name: "Production",
            sourceKind: .prometheus,
            urlString: "https://prometheus.example.com",
            promQL: "up{job=\"api\"}",
            authentication: HTTPAuthentication(
                kind: .basic,
                username: "reader",
                password: "secret"
            ),
            requestHeaders: [RequestHeader(name: "X-API-Key", value: "token")],
            parser: ParserConfiguration(
                kind: .javaScript,
                jsonPath: "$.unused",
                scriptBody: "function parse(response) { return 1; }"
            ),
            displayTemplate: "API ${value}%",
            statusIndicator: StatusIndicatorConfiguration(
                isEnabled: true,
                rules: [
                    StatusIndicatorRule(value: 70, color: .yellow),
                    StatusIndicatorRule(value: 90, color: .pink)
                ]
            ),
            refreshInterval: 300,
            refreshIntervalUnit: .minutes,
            requestTimeout: 25,
            isEnabled: false,
            showsInMenuBar: true,
            order: 3,
            runtime: runtime
        )

        let clone = makeMonitorClone(from: source, name: "Production Copy", order: 4)

        #expect(clone.id != source.id)
        #expect(clone.name == "Production Copy")
        #expect(clone.sourceKind == source.sourceKind)
        #expect(clone.urlString == source.urlString)
        #expect(clone.promQL == source.promQL)
        #expect(clone.authentication == source.authentication)
        #expect(clone.parser == source.parser)
        #expect(clone.displayTemplate == source.displayTemplate)
        #expect(clone.statusIndicator == source.statusIndicator)
        #expect(clone.refreshInterval == source.refreshInterval)
        #expect(clone.refreshIntervalUnit == source.refreshIntervalUnit)
        #expect(clone.requestTimeout == source.requestTimeout)
        #expect(clone.isEnabled == source.isEnabled)
        #expect(clone.showsInMenuBar == source.showsInMenuBar)
        #expect(clone.order == 4)
        #expect(clone.runtime == MonitorRuntimeState())

        let sourceHeader = try #require(source.requestHeaders.first)
        let clonedHeader = try #require(clone.requestHeaders.first)
        #expect(clonedHeader.id != sourceHeader.id)
        #expect(clonedHeader.name == sourceHeader.name)
        #expect(clonedHeader.value == sourceHeader.value)
    }
}
