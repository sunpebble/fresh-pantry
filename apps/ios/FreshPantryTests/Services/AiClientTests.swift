import Foundation
import Testing
@testable import FreshPantry

/// Error-mapping parity tests for `AiClient.chat`, driven by a stubbed
/// `URLProtocol` on an ephemeral `URLSession` (no live key / network). Each case
/// returns a crafted status + body and asserts the thrown `AiError` case AND its
/// localized message, built via the same `String(localized:)` API as the
/// implementation — the test host's language is whatever the run environment
/// picks, so expectations are format-equivalence, not a hardcoded language.
@MainActor
@Suite(.serialized)
struct AiClientTests {
    // MARK: Stub plumbing

    /// A process-wide stub registry — `URLProtocol` is instantiated by the loading
    /// system, so it can't carry per-call state; we key off a single handler set
    /// before each request. Tests run serially in this suite.
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func respond(status: Int, body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    private let settings = AiSettings(
        baseUrl: "https://example.com/v1",
        apiKey: "test-key",
        model: "gpt-4o",
        timeout: 30
    )

    private func chat() async throws -> String {
        try await AiClient.chat(
            settings: settings,
            messages: [.text("user", "hi")],
            session: stubbedSession()
        )
    }

    // MARK: notConfigured (short-circuits before any network)

    @Test func notConfiguredThrowsBeforeNetwork() async {
        let empty = AiSettings(baseUrl: "", apiKey: "", model: "")
        await #expect(throws: AiError.notConfigured) {
            try await AiClient.chat(settings: empty, messages: [.text("user", "hi")])
        }
    }

    // MARK: 200 success

    @Test func successReturnsChoiceContent() async throws {
        respond(status: 200, body: #"{"choices":[{"message":{"content":"解析结果"}}]}"#)
        let content = try await chat()
        #expect(content == "解析结果")
    }

    @Test func successWithNoChoicesThrowsParse() async {
        respond(status: 200, body: #"{"choices":[]}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.ai.parse \("no choices")")) }
    }

    @Test func successWithNonStringContentThrowsParse() async {
        respond(status: 200, body: #"{"choices":[{"message":{"content":123}}]}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.ai.emptyResponse")) }
    }

    // MARK: Auth / rate / server / 404 / unexpected

    @Test func status401MapsToAuth() async {
        respond(status: 401, body: "nope")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth(String(localized: "error.ai.authFailed \(401)")) }
    }

    @Test func status403MapsToAuth() async {
        respond(status: 403, body: "forbidden")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth(String(localized: "error.ai.authFailed \(403)")) }
    }

    @Test func status401WithAuthExpiredCodeMapsToLocalizedMessage() async {
        respond(status: 401, body: #"{"error":{"code":"auth_expired","message":"token expired"}}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth(String(localized: "error.ai.authExpired")) }
    }

    @Test func status401WithAuthMissingCodeMapsToLocalizedMessage() async {
        respond(status: 401, body: #"{"error":{"code":"auth_missing","message":"missing credentials"}}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth(String(localized: "error.ai.authExpired")) }
    }

    @Test func status429MapsToBusyNetwork() async {
        respond(status: 429, body: "slow down")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network(String(localized: "error.ai.busy")) }
    }

    @Test func testQuotaExhaustedCodeMapsToLocalizedMessage() async {
        respond(status: 429, body: #"{"error":{"code":"quota_exhausted","message":"今天的 AI 次数用完了，明天再来"}}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network(String(localized: "error.ai.quotaExhausted")) }
    }

    @Test func status500MapsToServerError() async {
        respond(status: 500, body: "boom")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network(String(localized: "error.ai.serverError \(500)")) }
    }

    @Test func status404MapsToBaseUrlHint() async {
        respond(status: 404, body: "not found")
        await #expect {
            try await chat()
        } throws: {
            ($0 as? AiError) == .network(String(localized: "error.ai.notFound"))
        }
    }

    @Test func unexpectedStatusIncludesTrimmedBody() async {
        respond(status: 418, body: "  teapot detail  ")
        await #expect {
            try await chat()
        } throws: {
            ($0 as? AiError) == .network(String(localized: "error.ai.unexpectedStatus \(418) \("：teapot detail")"))
        }
    }

    @Test func unexpectedStatusTruncatesLongBodyTo120Chars() async {
        let long = String(repeating: "x", count: 200)
        respond(status: 418, body: long)
        await #expect {
            try await chat()
        } throws: {
            let suffix = "：\(String(repeating: "x", count: 120))…"
            return ($0 as? AiError) == .network(String(localized: "error.ai.unexpectedStatus \(418) \(suffix)"))
        }
    }
}
