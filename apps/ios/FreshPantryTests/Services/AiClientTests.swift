import Foundation
import Testing
@testable import FreshPantry

/// Error-mapping parity tests for `AiClient.chat`, driven by a stubbed
/// `URLProtocol` on an ephemeral `URLSession` (no live key / network). Each case
/// returns a crafted status + body and asserts the thrown `AiError` case AND its
/// Chinese message — the UI keys off both, so they must match the Dart client.
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
        } throws: { ($0 as? AiError) == .parse("响应中无 choices") }
    }

    @Test func successWithNonStringContentThrowsParse() async {
        respond(status: 200, body: #"{"choices":[{"message":{"content":123}}]}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .parse("响应中无 content") }
    }

    // MARK: Auth / rate / server / 404 / unexpected

    @Test func status401MapsToAuth() async {
        respond(status: 401, body: "nope")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth("认证失败 (401)") }
    }

    @Test func status403MapsToAuth() async {
        respond(status: 403, body: "forbidden")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .auth("认证失败 (403)") }
    }

    @Test func status429MapsToBusyNetwork() async {
        respond(status: 429, body: "slow down")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network("服务繁忙 (429)") }
    }

    @Test func status429PassesThroughServerErrorMessage() async {
        respond(status: 429, body: #"{"error":{"message":"今天的 AI 次数用完了，明天再来"}}"#)
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network("今天的 AI 次数用完了，明天再来") }
    }

    @Test func status500MapsToServerError() async {
        respond(status: 500, body: "boom")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network("服务错误 (500)") }
    }

    @Test func status404MapsToBaseUrlHint() async {
        respond(status: 404, body: "not found")
        await #expect {
            try await chat()
        } throws: {
            ($0 as? AiError) == .network(
                "接口不存在 (404)。Base URL 应填写到 /v1，例如 https://example.com/v1，不要包含 /chat/completions"
            )
        }
    }

    @Test func unexpectedStatusIncludesTrimmedBody() async {
        respond(status: 418, body: "  teapot detail  ")
        await #expect {
            try await chat()
        } throws: { ($0 as? AiError) == .network("意外状态 (418)：teapot detail") }
    }

    @Test func unexpectedStatusTruncatesLongBodyTo120Chars() async {
        let long = String(repeating: "x", count: 200)
        respond(status: 418, body: long)
        await #expect {
            try await chat()
        } throws: {
            ($0 as? AiError) == .network("意外状态 (418)：\(String(repeating: "x", count: 120))…")
        }
    }
}
