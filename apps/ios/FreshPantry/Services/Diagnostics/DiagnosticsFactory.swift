import Foundation

/// 按构建配置建对应 sink,门控逻辑刻意镜像 `SentryBootstrap.start`:
/// - DEBUG → OSLog(永不碰 Sentry)
/// - Release + 有 Sentry 配置 → Sentry
/// - Release + 无配置(OSS checkout / 空 Secrets)→ Noop
enum DiagnosticsFactory {
    static func make(sentryConfig: SentryConfig?) -> Diagnostics {
        #if DEBUG
        return OSLogDiagnostics()
        #else
        return sentryConfig == nil ? NoopDiagnostics() : SentryDiagnostics()
        #endif
    }
}
