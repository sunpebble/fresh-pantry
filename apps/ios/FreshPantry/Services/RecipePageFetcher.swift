import Foundation

/// The injected page-fetch seam — a closure that downloads a recipe page and
/// returns its stripped readable text. Keeps `AiRecipeParser` testable without
/// the network (the prod call wraps `RecipePageFetcher.fetchText`). Mirrors the
/// Dart `typedef RecipePageFetcherFn = Future<String> Function(String url)`.
typealias RecipePageFetcherFn = @Sendable (String) async throws -> String

/// Supported recipe-source hosts (services INVARIANT #13). The gate is enforced
/// in BOTH `ensureRecipeUrl` (the url-extract side) and `fetchText` (the fetcher
/// side) so a lookalike host can never slip into the LLM prompt. Subdomains are
/// accepted; lookalikes ("notxiachufang.com", "xiachufang.com.evil.com") are
/// rejected. Ported from `share_intent_service.dart` `kSupportedRecipeHosts` /
/// `isSupportedRecipeHost`.
private let supportedRecipeHosts = ["lanfanapp.com", "xiachufang.com"]

/// True when `host` equals a supported domain OR is one of its subdomains
/// (`host == domain` OR `host.hasSuffix("." + domain)`). Case-insensitive.
func isSupportedRecipeHost(_ host: String) -> Bool {
    let lower = host.lowercased()
    return supportedRecipeHosts.contains { domain in
        lower == domain || lower.hasSuffix(".\(domain)")
    }
}

/// True when the URL's host is a supported recipe host (subdomains accepted).
func isSupportedRecipeHost(_ url: URL) -> Bool {
    guard let host = url.host else { return false }
    return isSupportedRecipeHost(host)
}

/// Extracts + normalizes a recipe URL from raw input (a bare URL or pasted text
/// that contains one), requiring only a valid http(s) URL. Returns the normalized
/// URL string; throws `AiError.parse(…)` with a Chinese message when the input is
/// missing a URL or is not http(s).
///
/// #4: the host whitelist was RELAXED here — the explicit "URL 导入" path now
/// accepts any web page (正文 / 视频描述 / 字幕 are stripped to text and fed to the
/// AI, which returns an error when a page has no recipe). The whitelist still
/// gates `extractSupportedRecipeURL` (clipboard auto-detect) so we don't offer to
/// import every random link a user copies.
func ensureRecipeUrl(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw AiError.parse("请填入合法的食谱链接")
    }

    // Accept a bare URL or pasted text — pull the first http(s) URL out.
    var candidate = trimmed
    if let extracted = extractFirstURLString(in: trimmed) {
        candidate = extracted
    } else if !trimmed.lowercased().hasPrefix("http") {
        // Bare host like "example.com/recipe/123" — prefix a scheme so it parses.
        candidate = "https://\(trimmed)"
    }

    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          let host = url.host, host.contains(".")
    else {
        // A bare sentence ("这不是一个链接") coerces to https://<text> with a
        // dot-less host → rejected here, so only real web URLs get through.
        throw AiError.parse("请填入合法的 http(s) 链接")
    }

    return url.absoluteString
}

/// First `https?://…` URL in `text` whose host is a supported recipe host, else
/// nil. Mirrors the Dart `extractUrl` used by clipboard detection: requires an
/// EXPLICIT http(s) URL (no bare-host coercion, unlike `ensureRecipeUrl`) and
/// applies the host gate (services INVARIANT #13) so only懒饭/下厨房 links are offered.
func extractSupportedRecipeURL(in text: String) -> String? {
    guard let candidate = extractFirstURLString(in: text),
          let url = URL(string: candidate),
          let host = url.host, isSupportedRecipeHost(host)
    else { return nil }
    return candidate
}

/// First `https?://…` substring of `text`, or nil. Mirrors the Dart
/// `extractUrl` regex `https?://[^\s)\]"]+` (host-gate applied by the caller).
private func extractFirstURLString(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s)\]"]+"#) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let matchRange = Range(match.range, in: text)
    else { return nil }
    return String(text[matchRange])
}

/// iPhone Safari UA — some recipe hosts gate non-browser clients (parity with
/// the Dart fetcher's `_mobileSafariUserAgent`).
private let mobileSafariUserAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

/// Downloads a recipe page and strips it to readable text for the LLM prompt.
/// Stateless `enum` namespace. Ported from `lib/services/recipe_page_fetcher.dart`.
enum RecipePageFetcher {
    /// GETs the page (re-validating the host gate, INVARIANT #13), decodes the
    /// HTML, and returns `extractRecipePageText` (body truncated to 80000 chars,
    /// INVARIANT #14). `session` is injectable so tests can drive a stubbed
    /// `URLProtocol`. Transport / non-200 failures map to `AiError.network`.
    static func fetchText(_ url: String, session: URLSession = .shared) async throws -> String {
        let normalized = try ensureRecipeUrl(url)
        guard let requestURL = URL(string: normalized) else {
            throw AiError.parse("请填入合法的 http(s) 链接")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(mobileSafariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AiError.network("网页抓取失败：请求超时")
        } catch is CancellationError {
            throw AiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw AiError.cancelled
        } catch {
            throw AiError.network("网页抓取失败：\(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AiError.network("网页抓取失败 (\(status))")
        }

        // `allowMalformed`-style lenient decode: UTF-8 first, then Latin-1 so a
        // partial-byte page still yields text rather than throwing.
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = extractRecipePageText(html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AiError.parse("网页中没有可解析的食谱内容")
        }
        return text
    }
}

/// HTML → readable text for the prompt. Builds parts joined by "\n\n": 标题 /
/// 摘要 / 封面图片 / 正文 where 正文 has `<script>`/`<style>` blocks removed, all
/// tags stripped to spaces, whitespace collapsed, and the body TRUNCATED to
/// 80000 chars (services INVARIANT #14). Ported from Dart `extractRecipePageText`.
func extractRecipePageText(_ html: String) -> String {
    var parts: [String] = []

    if let title = decodeHtmlEntities(firstGroup(in: html, pattern: "<title[^>]*>([^<]+)")?.trimmed),
       !title.isEmpty {
        parts.append("标题: \(title)")
    }

    if let description = decodeHtmlEntities(
        firstGroup(in: html, pattern: #"name=["']description["']\s+content=["']([^"']*)["']"#)?.trimmed
    ), !description.isEmpty {
        parts.append("摘要: \(description)")
    }

    if let cover = extractCoverImageUrl(html), !cover.isEmpty {
        parts.append("封面图片: \(cover)")
    }

    var body = html
    body = replacing(body, pattern: "<script[\\s\\S]*?</script>", with: " ")
    body = replacing(body, pattern: "<style[\\s\\S]*?</style>", with: " ")
    body = replacing(body, pattern: "<[^>]+>", with: " ")
    body = replacing(body, pattern: "\\s+", with: " ").trimmed
    if body.count > 80_000 {
        body = String(body.prefix(80_000))
    }
    if !body.isEmpty {
        parts.append("正文: \(body)")
    }

    return parts.joined(separator: "\n\n")
}

// MARK: - Cover image extraction (parity with Dart `_extractCoverImageUrl`)

private func extractCoverImageUrl(_ html: String) -> String? {
    for tag in allMatches(in: html, pattern: "<meta\\b[^>]*>", group: 0) {
        let key = htmlAttribute(tag, "property")
            ?? htmlAttribute(tag, "name")
            ?? htmlAttribute(tag, "itemprop")
        switch key?.lowercased() {
        case "og:image", "twitter:image", "image":
            let content = decodeHtmlEntities(htmlAttribute(tag, "content"))
            if isHttpUrl(content) { return content }
        default:
            continue
        }
    }

    for rawScript in allMatches(
        in: html,
        pattern: #"<script\b[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
        group: 1
    ) {
        guard let rawJson = decodeHtmlEntities(rawScript.trimmed), !rawJson.isEmpty,
              let data = rawJson.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { continue }
        if let imageUrl = imageUrlFromStructuredData(value), isHttpUrl(imageUrl) {
            return imageUrl
        }
    }

    return nil
}

private func imageUrlFromStructuredData(_ value: JSONValue, imageContext: Bool = false) -> String? {
    switch value {
    case let .string(string):
        return imageContext ? string : nil
    case let .array(items):
        for item in items {
            if let url = imageUrlFromStructuredData(item, imageContext: imageContext), isHttpUrl(url) {
                return url
            }
        }
        return nil
    case let .object(map):
        if let image = map["image"],
           let direct = imageUrlFromStructuredData(image, imageContext: true),
           isHttpUrl(direct) {
            return direct
        }

        let isImageObject = imageContext || isImageObjectType(map["@type"])
        if isImageObject {
            for key in ["url", "contentUrl", "thumbnailUrl"] {
                if let nested = map[key],
                   let url = imageUrlFromStructuredData(nested, imageContext: true),
                   isHttpUrl(url) {
                    return url
                }
            }
        }

        for (key, entry) in map where key != "author" && key != "aggregateRating" {
            if let url = imageUrlFromStructuredData(entry), isHttpUrl(url) {
                return url
            }
        }
        return nil
    case .int, .double, .bool, .null:
        return nil
    }
}

private func isImageObjectType(_ value: JSONValue?) -> Bool {
    switch value {
    case .string("ImageObject"):
        return true
    case let .array(items):
        return items.contains(.string("ImageObject"))
    default:
        return false
    }
}

private func isHttpUrl(_ value: String?) -> Bool {
    guard let value, !value.isEmpty, let url = URL(string: value),
          let scheme = url.scheme?.lowercased()
    else { return false }
    return (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
}

// MARK: - HTML helpers (parity with the Dart regex utilities)

private func htmlAttribute(_ tag: String, _ name: String) -> String? {
    // `name\s*=\s*(['"])(.*?)\1`
    firstGroup(in: tag, pattern: "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(['\"])(.*?)\\1", group: 2)
}

private func decodeHtmlEntities(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return value }
    return value
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

// MARK: - Regex primitives

private func firstGroup(in input: String, pattern: String, group: Int = 1) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
        return nil
    }
    let range = NSRange(input.startIndex..., in: input)
    guard let match = regex.firstMatch(in: input, range: range),
          let groupRange = Range(match.range(at: group), in: input)
    else { return nil }
    return String(input[groupRange])
}

private func allMatches(in input: String, pattern: String, group: Int) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
        return []
    }
    let range = NSRange(input.startIndex..., in: input)
    return regex.matches(in: input, range: range).compactMap { match in
        guard let groupRange = Range(match.range(at: group), in: input) else { return nil }
        return String(input[groupRange])
    }
}

private func replacing(_ input: String, pattern: String, with template: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
        return input
    }
    let range = NSRange(input.startIndex..., in: input)
    return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
}
