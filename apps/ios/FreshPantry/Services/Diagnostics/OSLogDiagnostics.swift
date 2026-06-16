import Foundation
import os

/// 把诊断打到系统统一日志(subsystem `com.kunish.freshPantry`,category
/// `diagnostics`),开发期本地可见。DEBUG 工厂的默认 sink —— 永不进 Sentry,
/// 与 `SentryBootstrap` 在 DEBUG 整体禁用 Sentry 一致。
struct OSLogDiagnostics: Diagnostics {
    private static let logger = Logger(subsystem: "com.kunish.freshPantry", category: "diagnostics")

    func breadcrumb(_ name: String, _ tags: [String: String]) {
        Self.logger.debug("📊 \(name, privacy: .public) \(Self.format(tags), privacy: .public)")
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let err = error.map { String(describing: $0) } ?? "-"
        Self.logger.error(
            "❌ \(name, privacy: .public) \(Self.format(tags), privacy: .public) err=\(err, privacy: .public)"
        )
    }

    func log(_ level: DiagnosticLevel, _ message: String, _ tags: [String: String]) {
        let line = "📝 \(message) \(Self.format(tags))"
        switch level {
        case .debug: Self.logger.debug("\(line, privacy: .public)")
        case .info: Self.logger.info("\(line, privacy: .public)")
        case .warning: Self.logger.notice("\(line, privacy: .public)")   // notice = warning 级
        case .error: Self.logger.error("\(line, privacy: .public)")
        }
    }

    func count(_ key: String, by value: UInt, _ tags: [String: String]) {
        Self.logger.debug(
            "➕ \(key, privacy: .public) +\(value, privacy: .public) \(Self.format(tags), privacy: .public)"
        )
    }

    func distribution(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        Self.logger.debug(
            "📈 \(key, privacy: .public) \(value, privacy: .public)\(Self.unitLabel(unit), privacy: .public) \(Self.format(tags), privacy: .public)"
        )
    }

    func gauge(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        Self.logger.debug(
            "🎚️ \(key, privacy: .public) \(value, privacy: .public)\(Self.unitLabel(unit), privacy: .public) \(Self.format(tags), privacy: .public)"
        )
    }

    /// 指标单位的可读后缀(无量纲为空串),仅用于本地日志行的可读性。
    private static func unitLabel(_ unit: DiagnosticUnit) -> String {
        switch unit {
        case .milliseconds: return "ms"
        case .bytes: return "B"
        case .none: return ""
        case .generic(let value): return value
        }
    }

    private static func format(_ tags: [String: String]) -> String {
        tags.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
