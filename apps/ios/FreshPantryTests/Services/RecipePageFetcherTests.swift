import Foundation
import Testing
@testable import FreshPantry

/// Host-gate + URL-normalization tests for `isSupportedRecipeHost` /
/// `ensureRecipeUrl` (INVARIANT #13: subdomains accepted, lookalikes rejected).
/// Pure — no network.
struct RecipeHostGateTests {
    // MARK: isSupportedRecipeHost

    @Test func acceptsExactSupportedHosts() {
        #expect(isSupportedRecipeHost("xiachufang.com"))
        #expect(isSupportedRecipeHost("lanfanapp.com"))
    }

    @Test func acceptsSubdomains() {
        #expect(isSupportedRecipeHost("www.xiachufang.com"))
        #expect(isSupportedRecipeHost("m.lanfanapp.com"))
        #expect(isSupportedRecipeHost("a.b.xiachufang.com"))
    }

    @Test func acceptsCaseInsensitively() {
        #expect(isSupportedRecipeHost("WWW.XiaChuFang.com"))
    }

    @Test func rejectsLookalikes() {
        #expect(!isSupportedRecipeHost("notxiachufang.com"))
        #expect(!isSupportedRecipeHost("xiachufang.com.evil.com"))
        #expect(!isSupportedRecipeHost("xiachufangXcom"))
        #expect(!isSupportedRecipeHost("example.com"))
        #expect(!isSupportedRecipeHost(""))
    }

    // MARK: ensureRecipeUrl

    @Test func ensureAcceptsSupportedFullUrls() throws {
        #expect(try ensureRecipeUrl("https://www.xiachufang.com/recipe/100").contains("xiachufang.com"))
        #expect(try ensureRecipeUrl("https://lanfanapp.com/recipe/abc").contains("lanfanapp.com"))
    }

    @Test func ensureAcceptsSubdomain() throws {
        let normalized = try ensureRecipeUrl("https://m.xiachufang.com/recipe/5")
        #expect(normalized.contains("m.xiachufang.com"))
    }

    @Test func ensureExtractsUrlFromPastedText() throws {
        let normalized = try ensureRecipeUrl("看看这个菜谱 https://www.xiachufang.com/recipe/9 很好吃")
        #expect(normalized == "https://www.xiachufang.com/recipe/9")
    }

    @Test func ensurePrefixesSchemeOnBareSupportedHost() throws {
        let normalized = try ensureRecipeUrl("xiachufang.com/recipe/7")
        #expect(normalized == "https://xiachufang.com/recipe/7")
    }

    // #4: the explicit URL-import path now accepts ANY http(s) web page (the
    // whitelist only still gates clipboard auto-detect, below).
    @Test func ensureNowAcceptsGenericHosts() throws {
        #expect(try ensureRecipeUrl("https://example.com/recipe").contains("example.com"))
        #expect(try ensureRecipeUrl("https://www.bilibili.com/video/BV1").contains("bilibili.com"))
        #expect(try ensureRecipeUrl("xiaohongshu.com/discovery/item/abc").contains("xiaohongshu.com"))
    }

    @Test func ensureRejectsNonHttpScheme() {
        #expect(throws: AiError.self) { try ensureRecipeUrl("ftp://xiachufang.com/r/1") }
    }

    @Test func ensureRejectsNonUrlString() {
        // A dot-less bare sentence must not coerce into a valid URL.
        #expect(throws: AiError.self) { try ensureRecipeUrl("这不是一个链接") }
        #expect(throws: AiError.self) { try ensureRecipeUrl("   ") }
    }

    // Clipboard auto-detect stays conservative — only known recipe hosts.
    @Test func clipboardDetectStillWhitelisted() {
        #expect(extractSupportedRecipeURL(in: "看 https://www.xiachufang.com/recipe/9") != nil)
        #expect(extractSupportedRecipeURL(in: "看 https://example.com/recipe") == nil)
    }
}

/// `extractRecipePageText` HTML→text stripping + the 80000-char truncation
/// (INVARIANT #14). Pure — no network.
struct RecipePageTextTests {
    @Test func stripsTagsAndCollapsesWhitespace() {
        let html = "<html><head><title>番茄炒蛋</title></head><body>"
            + "<script>var x = 1;</script><style>.a{color:red}</style>"
            + "<p>食材:   番茄   2   个</p></body></html>"
        let text = extractRecipePageText(html)
        #expect(text.contains("标题: 番茄炒蛋"))
        #expect(text.contains("食材: 番茄 2 个"))
        // Script/style contents are removed.
        #expect(!text.contains("var x"))
        #expect(!text.contains("color:red"))
        // No raw tags survive.
        #expect(!text.contains("<p>"))
        #expect(!text.contains("</body>"))
    }

    @Test func decodesTitleEntities() {
        let html = "<title>A &amp; B &lt;C&gt;</title><body>x</body>"
        let text = extractRecipePageText(html)
        #expect(text.contains("标题: A & B <C>"))
    }

    @Test func extractsOgImageCover() {
        let html = #"<head><meta property="og:image" content="https://img.example.com/cover.jpg"></head><body>正文</body>"#
        let text = extractRecipePageText(html)
        #expect(text.contains("封面图片: https://img.example.com/cover.jpg"))
    }

    @Test func bodyTruncatedTo80000() {
        let filler = String(repeating: "字", count: 90_000)
        let html = "<body>\(filler)</body>"
        let text = extractRecipePageText(html)
        // The 正文 section's body must be capped at 80000 chars.
        guard let bodyRange = text.range(of: "正文: ") else {
            Issue.record("missing 正文 section")
            return
        }
        let body = String(text[bodyRange.upperBound...])
        #expect(body.count == 80_000)
    }
}

/// `RecipePageFetcher.fetchText` over a stubbed `URLProtocol` — no real network.
/// Serialized like `AiClientTests` because the stub handler is process-wide.
@Suite(.serialized)
struct RecipePageFetcherTests {
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

    @Test func returnsStrippedText() async throws {
        respond(
            status: 200,
            body: "<title>红烧肉</title><body><script>bad()</script><p>做法 简单</p></body>"
        )
        let text = try await RecipePageFetcher.fetchText(
            "https://www.xiachufang.com/recipe/1",
            session: stubbedSession()
        )
        #expect(text.contains("标题: 红烧肉"))
        #expect(text.contains("做法 简单"))
        #expect(!text.contains("bad()"))
        #expect(!text.contains("<p>"))
    }

    @Test func truncatesBodyTo80000() async throws {
        let filler = String(repeating: "x", count: 100_000)
        respond(status: 200, body: "<body>\(filler)</body>")
        let text = try await RecipePageFetcher.fetchText(
            "https://www.xiachufang.com/recipe/2",
            session: stubbedSession()
        )
        guard let bodyRange = text.range(of: "正文: ") else {
            Issue.record("missing 正文 section")
            return
        }
        #expect(String(text[bodyRange.upperBound...]).count == 80_000)
    }

    @Test func nonOkStatusMapsToNetworkError() async {
        respond(status: 503, body: "down")
        await #expect {
            try await RecipePageFetcher.fetchText(
                "https://www.xiachufang.com/recipe/3",
                session: stubbedSession()
            )
        } throws: { ($0 as? AiError) == .network(String(localized: "error.recipeParse.fetchStatus 503")) }
    }

    @Test func emptyBodyThrowsParse() async {
        respond(status: 200, body: "<html><body>   </body></html>")
        await #expect {
            try await RecipePageFetcher.fetchText(
                "https://www.xiachufang.com/recipe/4",
                session: stubbedSession()
            )
        } throws: { ($0 as? AiError) == .parse(String(localized: "error.recipeParse.noContent")) }
    }

    // #4: a generic (non-whitelisted) host is now fetched + parsed rather than
    // rejected before the request.
    @Test func genericHostNowFetched() async throws {
        respond(status: 200, body: "<html><body><h1>家常菜</h1>番茄炒蛋 做法步骤</body></html>")
        let text = try await RecipePageFetcher.fetchText(
            "https://example.com/recipe",
            session: stubbedSession()
        )
        #expect(text.contains("番茄炒蛋"))
    }
}
