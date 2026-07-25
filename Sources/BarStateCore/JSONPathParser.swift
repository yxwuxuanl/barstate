import CoreFoundation
import Foundation

public enum JSONPathParser {
    private enum Token: Equatable {
        case property(String)
        case index(Int)
    }

    public static func validate(_ path: String) throws {
        _ = try tokens(in: path)
    }

    public static func number(at path: String, in root: Any) throws -> Double {
        var current: Any = root

        for token in try tokens(in: path) {
            switch token {
            case let .property(key):
                guard let object = current as? [String: Any], let value = object[key] else {
                    throw MonitoringError.valueNotFound
                }
                current = value
            case let .index(index):
                guard let array = current as? [Any], array.indices.contains(index) else {
                    throw MonitoringError.valueNotFound
                }
                current = array[index]
            }
        }

        if let number = current as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID()
        {
            return try NumericResultParser.validate(number.doubleValue)
        }

        if let string = current as? String {
            return try NumericResultParser.parse(string)
        }

        throw MonitoringError.resultIsNotNumber
    }

    private static func tokens(in path: String) throws -> [Token] {
        guard path.first == "$" else {
            throw MonitoringError.jsonPathRootRequired
        }

        var tokens: [Token] = []
        var index = path.index(after: path.startIndex)

        while index < path.endIndex {
            switch path[index] {
            case ".":
                let start = path.index(after: index)
                var end = start
                while end < path.endIndex, path[end] != ".", path[end] != "[" {
                    end = path.index(after: end)
                }
                guard start < end else {
                    throw MonitoringError.jsonPathPropertyRequired
                }
                tokens.append(.property(String(path[start..<end])))
                index = end

            case "[":
                let start = path.index(after: index)
                guard let close = path[start...].firstIndex(of: "]") else {
                    throw MonitoringError.jsonPathClosingBracketRequired
                }
                let rawIndex = String(path[start..<close])
                guard !rawIndex.isEmpty,
                      rawIndex.allSatisfy(\.isNumber),
                      let arrayIndex = Int(rawIndex)
                else {
                    throw MonitoringError.jsonPathInvalidArrayIndex
                }
                tokens.append(.index(arrayIndex))
                index = path.index(after: close)

            default:
                throw MonitoringError.jsonPathInvalidAccess
            }
        }

        return tokens
    }
}
