import Foundation
import JavaScriptCore

public enum JavaScriptEvaluator {
    public static var defaultFunctionSource: String {
        """
        /**
         * @param {Object|string} response \(L10n.string("javascript.response_description"))
         * @returns {number|string}
         */
        function(response) {
            // return response.value
        }
        """
    }

    public static func normalizedFunctionSource(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultFunctionSource }
        guard !isFunctionSource(trimmed) else { return trimmed }

        let indentedBody = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
        return """
        function(response) {
        \(indentedBody)
        }
        """
    }

    public static func updatingResponseType(
        in source: String,
        bodyKind: ResponseBodyKind?
    ) -> String {
        let normalized = normalizedFunctionSource(source)
        let parameterType = bodyKind?.javaScriptParameterType ?? "Object|string"
        let replacement = " * @param {\(parameterType)} response \(L10n.string("javascript.response_description"))"
        let pattern = #"(?m)^[ \t]*\*[ \t]*@param[ \t]+\{[^}]+\}[ \t]+response.*$"#

        if let range = normalized.range(of: pattern, options: .regularExpression) {
            var updated = normalized
            updated.replaceSubrange(range, with: replacement)
            return updated
        }

        return """
        /**
        \(replacement)
         * @returns {number|string}
         */
        \(normalized)
        """
    }

    public static func evaluate(responseData: Data, scriptBody: String) throws -> Double {
        let response: Any
        if let json = try? JSONSerialization.jsonObject(
            with: responseData,
            options: [.fragmentsAllowed]
        ) {
            response = json
        } else if let text = String(data: responseData, encoding: .utf8) {
            response = text
        } else {
            throw MonitoringError.unsupportedResponseBody
        }

        guard let context = JSContext() else {
            throw MonitoringError.scriptRuntimeUnavailable
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString()
        }
        context.setObject(response, forKeyedSubscript: "__barStateResponse" as NSString)

        let functionSource = normalizedFunctionSource(scriptBody)
        let wrappedScript = """
        "use strict";
        (\(functionSource))(__barStateResponse)
        """

        guard let result = context.evaluateScript(wrappedScript) else {
            if let exceptionMessage {
                throw MonitoringError.script(exceptionMessage)
            }
            throw MonitoringError.scriptNoResult
        }
        if let exceptionMessage {
            throw MonitoringError.script(exceptionMessage)
        }
        if result.isNumber {
            return try NumericResultParser.validate(result.toDouble())
        }

        if result.isString, let string = result.toString() {
            return try NumericResultParser.parse(string)
        }

        throw MonitoringError.resultIsNotNumber
    }

    private static func isFunctionSource(_ source: String) -> Bool {
        var candidate = source[...]
        if candidate.hasPrefix("/**"), let commentEnd = candidate.range(of: "*/") {
            candidate = candidate[commentEnd.upperBound...]
                .drop(while: { $0.isWhitespace })
        }
        guard candidate.hasPrefix("function") else { return false }
        let remainder = candidate.dropFirst("function".count)
        guard let first = remainder.first else { return false }
        return first == "(" || first == "*" || first.isWhitespace
    }
}
