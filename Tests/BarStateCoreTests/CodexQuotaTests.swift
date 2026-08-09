import Foundation
import Testing
@testable import BarStateCore

struct CodexQuotaTests {
    @Test func loadsAccessTokenAndAccountID() throws {
        let authURL = try makeAuthFile(
            #"{"tokens":{"access_token":" access-token ","account_id":" account-123 "}}"#
        )
        defer { try? FileManager.default.removeItem(at: authURL.deletingLastPathComponent()) }

        let credentials = try CodexAuthFile.load(from: authURL)

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.accountID == "account-123")
    }

    @Test func rejectsMissingAuthFile() {
        let authURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("auth.json")

        #expect(throws: MonitoringError.codexAuthFileNotFound) {
            try CodexAuthFile.load(from: authURL)
        }
    }

    @Test func rejectsAuthFileWithoutAccessToken() throws {
        let authURL = try makeAuthFile(#"{"tokens":{"account_id":"account-123"}}"#)
        defer { try? FileManager.default.removeItem(at: authURL.deletingLastPathComponent()) }

        #expect(throws: MonitoringError.codexAccessTokenMissing) {
            try CodexAuthFile.load(from: authURL)
        }
    }

    @Test func buildsFixedAuthenticatedQuotaRequest() throws {
        let authURL = try makeAuthFile(
            #"{"tokens":{"access_token":"secret-token","account_id":"account-123"}}"#
        )
        defer { try? FileManager.default.removeItem(at: authURL.deletingLastPathComponent()) }
        let monitor = Monitor(
            name: "quota",
            sourceKind: .codexQuota,
            urlString: "https://untrusted.example.com",
            authentication: HTTPAuthentication(
                kind: .basic,
                username: "ignored",
                password: "ignored"
            ),
            requestHeaders: [RequestHeader(name: "X-Ignored", value: "ignored")],
            requestTimeout: 24
        )

        let request = try HTTPRequestBuilder.makeRequest(
            for: monitor,
            codexAuthFileURL: authURL
        )

        #expect(request.url?.absoluteString == CodexQuota.endpointURLString)
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 24)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
        #expect(request.value(forHTTPHeaderField: "X-Ignored") == nil)
    }

    @Test func parsesPrimaryWindowAsRemainingPercent() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":12.5}}}"#.utf8)

        let remaining = try CodexQuotaResponseParser.remainingPercent(from: data)

        #expect(remaining == 87.5)
    }

    @Test func rejectsMissingPrimaryWindow() {
        let data = Data(#"{"rate_limit":{"primary_window":null}}"#.utf8)

        #expect(throws: MonitoringError.codexQuotaMissing) {
            try CodexQuotaResponseParser.remainingPercent(from: data)
        }
    }

    @Test func rejectsOutOfRangeUsage() {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":101}}}"#.utf8)

        #expect(throws: MonitoringError.codexQuotaInvalid) {
            try CodexQuotaResponseParser.remainingPercent(from: data)
        }
    }

    @Test func snapshotKeepsQuotaButRemovesAccountIdentity() throws {
        let data = Data(
            #"{"user_id":"user-123","account_id":"account-123","email":"person@example.com","plan_type":"pro","rate_limit":{"primary_window":{"used_percent":12}}}"#.utf8
        )

        let snapshotData = CodexQuotaResponseParser.quotaOnlySnapshotData(from: data)
        let snapshotText = try #require(String(data: snapshotData, encoding: .utf8))

        #expect(snapshotText.contains("rate_limit"))
        #expect(snapshotText.contains("used_percent"))
        #expect(!snapshotText.contains("user-123"))
        #expect(!snapshotText.contains("account-123"))
        #expect(!snapshotText.contains("person@example.com"))
        #expect(!snapshotText.contains("plan_type"))
        #expect(try CodexQuotaResponseParser.remainingPercent(from: snapshotData) == 88)
    }

    private func makeAuthFile(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let authURL = directoryURL.appendingPathComponent("auth.json")
        try Data(contents.utf8).write(to: authURL, options: [.atomic])
        return authURL
    }
}
