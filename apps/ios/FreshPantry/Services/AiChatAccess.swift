import Foundation

/// 一次 AI 调用可用的传输通道。BYOK（用户自填 endpoint）优先且不受 Pro/限额约束；
/// 其次 Pro 用户走内置 worker 代理；否则引导购买。
enum AiAvailability: Equatable {
    case byok(AiSettings)
    case builtIn
    case needsPro
}

/// 内置 AI 传输的解析与构造。纯函数 + 一个闭包工厂，保持可测。
enum AiChatAccess {
    static let builtInModel = "deepseek-v4-flash"

    static func resolve(byok: AiSettings, isPro: Bool) -> AiAvailability {
        if byok.isConfigured { return .byok(byok) }
        return isPro ? .builtIn : .needsPro
    }

    /// worker 基址 + Supabase access token → 可直接喂给 AiClient 的 AiSettings。
    /// normalizeAiBaseUrl 会给不含 /v1 的 base 补 /v1，所以 worker 路由是
    /// /ai/v1/chat/completions —— 这里只到 /ai。
    static func builtInSettings(apiBaseURL: URL, accessToken: String) -> AiSettings {
        AiSettings(
            baseUrl: apiBaseURL.appendingPathComponent("ai").absoluteString,
            apiKey: accessToken,
            model: builtInModel,
            timeout: 120
        )
    }

    /// 内置通道的 chat 闭包。每次调用现取 session（token 会自动刷新，不能缓存）。
    static func builtInChatFn(
        clientProvider: SupabaseClientProvider,
        apiBaseURL: URL,
        responseFormat: [String: JSONValue]? = nil
    ) -> AiChatFn {
        let client = clientProvider.client
        return { messages in
            guard let client else {
                throw AiError.notConfigured
            }
            guard let session = try? await client.auth.session else {
                throw AiError.auth("请先登录后再使用 AI 功能")
            }
            let settings = builtInSettings(apiBaseURL: apiBaseURL, accessToken: session.accessToken)
            return try await AiClient.chat(
                settings: settings,
                messages: messages,
                responseFormat: responseFormat
            )
        }
    }
}
