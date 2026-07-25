import Foundation
import Testing
@testable import BarStateCore

struct JSONPathParserTests {
    @Test func readsNestedPropertyAndArrayIndex() throws {
        let json: [String: Any] = [
            "data": [
                "items": [
                    ["value": 30.5]
                ]
            ]
        ]

        let value = try JSONPathParser.number(at: "$.data.items[0].value", in: json)
        #expect(value == 30.5)
    }

    @Test func rejectsUnsupportedSyntax() {
        #expect(throws: MonitoringError.self) {
            try JSONPathParser.validate("$.items[*].value")
        }
    }

    @Test func rejectsBooleanAsNumber() {
        #expect(throws: MonitoringError.resultIsNotNumber) {
            try JSONPathParser.number(at: "$.value", in: ["value": true])
        }
    }

    @Test func acceptsNumericStrings() throws {
        let integer = try JSONPathParser.number(at: "$.value", in: ["value": "30"])
        let decimal = try JSONPathParser.number(at: "$.value", in: ["value": "30.1"])

        #expect(integer == 30)
        #expect(decimal == 30.1)
    }

    @Test func rejectsNonNumericString() {
        #expect(throws: MonitoringError.resultIsNotNumber) {
            try JSONPathParser.number(at: "$.value", in: ["value": "thirty"])
        }
    }
}
