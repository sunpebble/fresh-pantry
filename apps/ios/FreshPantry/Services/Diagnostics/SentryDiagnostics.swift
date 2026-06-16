#if !DEBUG
import Foundation
// `@preconcurrency`:sentry-cocoa 9.17 的 `SentrySDK.metrics`(可变 static var)未加
// 并发标注,Swift 6 `complete` 隔离下直读会判为「访问共享可变状态不安全」的硬错误。
// 该属性 getter 返回的 metrics API 单例本就为跨线程并发埋点设计,降级为告警安全可接受。
@preconcurrency import Sentry

/// 把诊断路由到 Sentry。仅在非 DEBUG 构建编译(与 `SentryBootstrap` 一致 ——
/// 它同样 `#if !DEBUG` 包裹每个 Sentry 调用)。假定 `SentryBootstrap.start` 已
/// 启动 SDK;若未启动,这些调用在 sentry-cocoa 内部是无害 no-op。
///
/// API 形态(sentry-cocoa 9.17):`Breadcrumb(level:category:)` + `.message`/
/// `.data`、`SentrySDK.addBreadcrumb`、`SentrySDK.capture(error:block:)` 带
/// `Scope.setTag`/`fingerprint`、`Event(level:)` + `SentryMessage(formatted:)` +
/// `.tags`/`.fingerprint` + `SentrySDK.capture(event:)`;另:`SentrySDK.logger`
/// 的 trace/debug/info/warn/error/fatal(需 `options.enableLogs = true`)、
/// `SentrySDK.metrics` 的 count/distribution/gauge(`SentryAttributeValue`/
/// `SentryUnit`,需 `options.enableMetrics = true`)。
struct SentryDiagnostics: Diagnostics {
    func breadcrumb(_ name: String, _ tags: [String: String]) {
        let crumb = Breadcrumb(level: .info, category: "diagnostic")
        crumb.message = name
        if !tags.isEmpty { crumb.data = tags }
        SentrySDK.addBreadcrumb(crumb)
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let fingerprintClass = tags["errorClass"] ?? error.map(diagnosticErrorClass) ?? "logic"
        if let error {
            SentrySDK.capture(error: error) { scope in
                for (key, value) in tags { scope.setTag(value: value, key: key) }
                scope.setTag(value: name, key: "diagnostic")
                scope.setFingerprint([name, fingerprintClass])
            }
        } else {
            let event = Event(level: .error)
            event.message = SentryMessage(formatted: name)
            var merged = tags
            merged["diagnostic"] = name
            event.tags = merged
            event.fingerprint = [name, fingerprintClass]
            SentrySDK.capture(event: event)
        }

        // 把每次失败镜像到 Logs + Metrics —— 这样连非 `measure` 的直接失败(如同步
        // deadletter)也能进可观测,且 `measure` 失败路径只靠这里出错误日志(不再
        // 重复发 per-op 日志)。原始错误 message 仍不进属性,只用 errorClass。
        var logTags = tags
        logTags["diagnostic"] = name
        SentrySDK.logger.error(name, attributes: logTags as [String: Any])
        Self.metricsApi.count(
            key: "diagnostic.failure",
            value: 1,
            attributes: ["diagnostic": name, "errorClass": fingerprintClass]
        )
    }

    func log(_ level: DiagnosticLevel, _ message: String, _ tags: [String: String]) {
        let attributes = tags as [String: Any]
        switch level {
        case .debug: SentrySDK.logger.debug(message, attributes: attributes)
        case .info: SentrySDK.logger.info(message, attributes: attributes)
        case .warning: SentrySDK.logger.warn(message, attributes: attributes)   // 注意是 warn 非 warning
        case .error: SentrySDK.logger.error(message, attributes: attributes)
        }
    }

    func count(_ key: String, by value: UInt, _ tags: [String: String]) {
        Self.metricsApi.count(key: key, value: value, attributes: Self.attributes(tags))
    }

    func distribution(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        Self.metricsApi.distribution(
            key: key, value: value, unit: Self.unit(unit), attributes: Self.attributes(tags))
    }

    func gauge(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        Self.metricsApi.gauge(
            key: key, value: value, unit: Self.unit(unit), attributes: Self.attributes(tags))
    }

    /// `SentrySDK.metrics` 是 SDK 的可变 `static var`(设计上允许注入替换),在 Swift 6
    /// `complete` 隔离下直接读会被判为「访问共享可变状态不安全」。它的 getter 只是
    /// 返回 SDK 全局并发使用的 metrics API 单例,本就是为跨线程并发埋点设计。
    /// sentry-cocoa 9.17 尚未为该属性加并发标注,故经本静态 getter 统一读取;文件顶部
    /// `@preconcurrency import Sentry` 把这次跨界读取从错误降级为(可接受的)告警,
    /// 既不改 SDK,又把不安全读取面收敛到这一处。
    private static var metricsApi: any SentryMetricsApiProtocol {
        SentrySDK.metrics
    }

    /// 把低基数 `[String: String]` tag 升为指标属性 —— `String` 原生 conform
    /// `SentryAttributeValue`,直接逐值上抛即可。
    private static func attributes(_ tags: [String: String]) -> [String: SentryAttributeValue] {
        tags.mapValues { $0 as SentryAttributeValue }
    }

    /// SDK 无关单位 → `SentryUnit`。`.none` 映射为 `nil`(无量纲)。
    private static func unit(_ unit: DiagnosticUnit) -> SentryUnit? {
        switch unit {
        case .milliseconds: return .millisecond
        case .bytes: return .byte
        case .none: return nil
        case .generic(let value): return .generic(value)
        }
    }
}
#endif
