import Foundation
import Testing
@testable import BarStateCore

struct JavaScriptEvaluatorTests {
    @Test func returnsNumericResult() throws {
        let data = Data(#"{"usage": {"remaining": 40, "total": 100}}"#.utf8)
        let result = try JavaScriptEvaluator.evaluate(
            responseData: data,
            scriptBody: """
            function(response) {
                return response.usage.remaining / response.usage.total * 100
            }
            """
        )
        #expect(result == 40)
    }

    @Test func acceptsNumericStringResults() throws {
        let integerData = Data(#"{"value": "30"}"#.utf8)
        let decimalData = Data(#"{"value": "30.1"}"#.utf8)

        let integer = try JavaScriptEvaluator.evaluate(
            responseData: integerData,
            scriptBody: "function(response) { return response.value }"
        )
        let decimal = try JavaScriptEvaluator.evaluate(
            responseData: decimalData,
            scriptBody: "function(response) { return response.value }"
        )

        #expect(integer == 30)
        #expect(decimal == 30.1)
    }

    @Test func rejectsNonNumericStringResult() {
        let data = Data(#"{"value": "thirty"}"#.utf8)
        #expect(throws: MonitoringError.resultIsNotNumber) {
            try JavaScriptEvaluator.evaluate(
                responseData: data,
                scriptBody: "function(response) { return response.value }"
            )
        }
    }

    @Test func supportsLegacyFunctionBody() throws {
        let data = Data(#"{"value": 30}"#.utf8)
        let result = try JavaScriptEvaluator.evaluate(
            responseData: data,
            scriptBody: "return response.value"
        )

        #expect(result == 30)
        #expect(
            JavaScriptEvaluator.normalizedFunctionSource("return response.value")
                == "function(response) {\n    return response.value\n}"
        )
    }

    @Test func passesPlainTextResponseAsAString() throws {
        let result = try JavaScriptEvaluator.evaluate(
            responseData: Data("remaining=30.1".utf8),
            scriptBody: "function(response) { return response.split('=')[1] }"
        )

        #expect(result == 30.1)
    }

    @Test func normalizesOnlyTheJSDocResponseTypeToAUnion() {
        let original = """
        /**
         * @param {Object|string} response 响应内容
         * @returns {number|string}
         */
        function(response) {
            return response.value
        }
        """

        let normalized = JavaScriptEvaluator.normalizingResponseJSDoc(in: original)

        #expect(normalized.contains("@param {string|Object} response"))
        #expect(normalized.contains("return response.value"))
        #expect(!normalized.contains("Object|string"))
    }
}
