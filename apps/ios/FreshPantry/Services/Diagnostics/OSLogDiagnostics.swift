import Foundation
import os

/// 把诊断打到系统统一日志(subsystem `com.sunpebble.freshpantry`,category
/// `diagnostics`),开发期本地可见。DEBUG 工厂的默认 sink —— 永不进 Sentry,
/// 与 `SentryBootstrap` 在 DEBUG 整体禁用 Sentry 一致。
struct OSLogDiagnostics: Diagnostics {
    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "diagnostics")

    func breadcrumb(_ name: String, _ tags: [String: String]) {
        Self.logger.debug("📊 \(name, privacy: .public) \(Self.format(tags), privacy: .public)")
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let err = error.map { String(describing: $0) } ?? "-"
        Self.logger.error(
            "❌ \(name, privacy: .public) \(Self.format(tags), privacy: .public) err=\(err, privacy: .public)"
        )
    }

    private static func format(_ tags: [String: String]) -> String {
        tags.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
