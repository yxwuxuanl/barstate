import Darwin
import Foundation

public enum CodexQuota {
    public static let endpointURLString = "https://chatgpt.com/backend-api/wham/usage"
}

public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String
    public let accountID: String?

    public init(accessToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
    }
}

public enum CodexAuthFile {
    private struct Contents: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountID: String?

            private enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountID = "account_id"
            }
        }

        let tokens: Tokens?
    }

    public static var defaultURL: URL {
        let homeDirectory: String
        if let passwordEntry = getpwuid(getuid()),
           let path = passwordEntry.pointee.pw_dir
        {
            homeDirectory = String(cString: path)
        } else {
            homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    public static func load(from url: URL = defaultURL) throws -> CodexCredentials {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw MonitoringError.codexAuthFileNotFound
        } catch {
            throw MonitoringError.codexAuthFileUnreadable
        }

        let contents: Contents
        do {
            contents = try JSONDecoder().decode(Contents.self, from: data)
        } catch {
            throw MonitoringError.codexAuthFileUnreadable
        }

        guard let accessToken = contents.tokens?.accessToken?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty
        else {
            throw MonitoringError.codexAccessTokenMissing
        }
        let accountID = contents.tokens?.accountID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCredentials(
            accessToken: accessToken,
            accountID: accountID?.isEmpty == false ? accountID : nil
        )
    }
}

public enum CodexQuotaResponseParser {
    private struct Envelope: Decodable {
        struct RateLimit: Decodable {
            struct Window: Decodable {
                let usedPercent: Double

                private enum CodingKeys: String, CodingKey {
                    case usedPercent = "used_percent"
                }
            }

            let primaryWindow: Window?

            private enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
            }
        }

        let rateLimit: RateLimit?

        private enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
        }
    }

    public static func remainingPercent(from data: Data) throws -> Double {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw MonitoringError.invalidJSON(error.localizedDescription)
        }

        guard let usedPercent = envelope.rateLimit?.primaryWindow?.usedPercent else {
            throw MonitoringError.codexQuotaMissing
        }
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
            throw MonitoringError.codexQuotaInvalid
        }
        return 100 - usedPercent
    }

    public static func quotaOnlySnapshotData(from data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rateLimit = dictionary["rate_limit"],
              JSONSerialization.isValidJSONObject(["rate_limit": rateLimit]),
              let sanitized = try? JSONSerialization.data(
                  withJSONObject: ["rate_limit": rateLimit],
                  options: [.sortedKeys]
              )
        else {
            return Data("{}".utf8)
        }
        return sanitized
    }
}
