import Foundation

public enum RequestTemplateResolver {
    public static let timestampPlaceholder = "${TIMESTAMP}"

    public static func resolve(_ template: String, at date: Date) -> String {
        let timestamp = String(Int64(date.timeIntervalSince1970.rounded(.down)))
        return template.replacingOccurrences(of: timestampPlaceholder, with: timestamp)
    }
}
