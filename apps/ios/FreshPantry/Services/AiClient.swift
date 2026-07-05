import Foundation

/// AI error hierarchy mirroring the Dart `AiException` sealed class. The Chinese
/// `message` text is keyed off by the UI, so it is preserved VERBATIM (services
/// invariant #1). Ported from `lib/services/ai_client.dart`.
enum AiError: Error, Equatable {
    case notConfigured
    case network(String)
    case auth(String)
    case parse(String)
    case cancelled

    /// Chinese user-facing message (parity with the Dart exceptions).
    var message: String {
        switch self {
        case .notConfigured: return "AI 服务未配置"
        case let .network(text): return text
        case let .auth(text): return text
        case let .parse(text): return text
        case .cancelled: return "已取消"
        }
    }
}

/// One content part of a chat message — plain text or an image data URL. Mirrors
/// the Dart `AiContent` factories. The `image_url` case exists for the deferred
/// vision slice; the text paste-import flow only uses `.text`.
struct AiContent: Encodable, Sendable, Equatable {
    enum Kind: String, Sendable { case text, imageURL }

    let kind: Kind
    let text: String?
    let imageDataURL: String?

    static func text(_ text: String) -> AiContent {
        AiContent(kind: .text, text: text, imageDataURL: nil)
    }

    static func imageDataURL(_ url: String) -> AiContent {
        AiContent(kind: .imageURL, text: nil, imageDataURL: url)
    }

    private enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    private enum ImageKeys: String, CodingKey { case url }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .text:
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL:
            try container.encode("image_url", forKey: .type)
            var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
            try image.encode(imageDataURL, forKey: .url)
        }
    }
}

/// A chat message (role + content parts). Encodes to `{role, content}` where a
/// single text part collapses `content` to a plain string (OpenAI accepts both),
/// else an array of typed content objects. Mirrors the Dart `AiMessage`.
struct AiMessage: Encodable, Sendable, Equatable {
    let role: String
    let content: [AiContent]

    static func text(_ role: String, _ text: String) -> AiMessage {
        AiMessage(role: role, content: [.text(text)])
    }

    /// User message bundling a prompt + an image data URL — kept for the deferred
    /// vision slice (no caller in the text paste-import flow).
    static func userWithImage(_ text: String, _ dataURL: String) -> AiMessage {
        AiMessage(role: "user", content: [.text(text), .imageDataURL(dataURL)])
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if content.count == 1, content[0].kind == .text {
            try container.encode(content[0].text, forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
    }
}

/// OpenAI-compatible chat-completions client. Stateless `enum` namespace (the
/// Dart `AiClient` is all-static). Maps every HTTP status branch to an `AiError`
/// with the exact Chinese message the Dart client produces.
enum AiClient {
    /// POSTs a chat-completions request and returns `choices[0].message.content`.
    /// `session` is injectable so tests can drive a stubbed `URLProtocol`.
    static func chat(
        settings: AiSettings,
        messages: [AiMessage],
        responseFormat: [String: JSONValue]? = nil,
        session: URLSession = .shared
    ) async throws -> String {
        guard settings.isConfigured else { throw AiError.notConfigured }

        let url = endpointURL(settings.baseUrl)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = settings.timeout
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encodeBody(settings: settings, messages: messages, responseFormat: responseFormat)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AiError.network("请求超时")
        } catch is CancellationError {
            throw AiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw AiError.cancelled
        } catch {
            throw AiError.network("网络错误：\(error.localizedDescription)")
        }

        try Task.checkCancellation()

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        try mapStatus(status, body: data)

        return try decodeContent(data)
    }

    // MARK: - Body / URL

    /// `normalizeAiBaseUrl(baseUrl)` joined with `/chat/completions` (strip a
    /// trailing slash on the base, ensure a single leading slash on the path).
    private static func endpointURL(_ baseUrl: String) -> URL {
        let base = normalizeAiBaseUrl(baseUrl)
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        // `URL(string:)` can fail on stray characters; fall back so we still hit
        // the error-mapping path rather than crashing on a malformed user input.
        return URL(string: "\(trimmedBase)/chat/completions") ?? URL(string: "https://invalid.invalid/chat/completions")!
    }

    private static func encodeBody(
        settings: AiSettings,
        messages: [AiMessage],
        responseFormat: [String: JSONValue]?
    ) throws -> Data {
        let body = RequestBody(
            model: settings.model,
            messages: messages,
            temperature: 0.2,
            responseFormat: responseFormat
        )
        return try JSONEncoder().encode(body)
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [AiMessage]
        let temperature: Double
        let responseFormat: [String: JSONValue]?

        private enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case responseFormat = "response_format"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encode(temperature, forKey: .temperature)
            // Omitted entirely when nil (Dart `?` spread parity).
            try container.encodeIfPresent(responseFormat, forKey: .responseFormat)
        }
    }

    // MARK: - Status mapping (parity with the Dart status branches)

    private static func mapStatus(_ status: Int, body: Data) throws {
        switch status {
        case 200:
            return
        case 401, 403:
            throw AiError.auth("认证失败 (\(status))")
        case 429:
            // 内置 worker 的日限额会带中文 error.message（如"今天的 AI 次数用完了，明天再来"），
            // 优先透传；无 body 时保留原文案。
            if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let err = root["error"] as? [String: Any],
               let message = err["message"] as? String, !message.isEmpty {
                throw AiError.network(message)
            }
            throw AiError.network("服务繁忙 (429)")
        case 404:
            throw AiError.network(
                "接口不存在 (404)。Base URL 应填写到 /v1，例如 https://example.com/v1，不要包含 /chat/completions"
            )
        case 500...:
            throw AiError.network("服务错误 (\(status))")
        default:
            let detail = (String(data: body, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix: String
            if detail.isEmpty {
                suffix = ""
            } else if detail.count > 120 {
                suffix = "：\(String(detail.prefix(120)))…"
            } else {
                suffix = "：\(detail)"
            }
            throw AiError.network("意外状态 (\(status))\(suffix)")
        }
    }

    // MARK: - Response decode

    private static func decodeContent(_ data: Data) throws -> String {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AiError.parse("解析响应失败: \(error.localizedDescription)")
        }
        guard let root = json as? [String: Any] else {
            throw AiError.parse("解析响应失败: 响应不是 JSON 对象")
        }
        guard let choices = root["choices"] as? [Any], !choices.isEmpty else {
            throw AiError.parse("响应中无 choices")
        }
        guard let first = choices.first as? [String: Any],
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AiError.parse("响应中无 content")
        }
        return content
    }
}
