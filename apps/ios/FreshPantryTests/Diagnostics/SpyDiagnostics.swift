import Foundation
@testable import FreshPantry

/// 记录每次诊断调用以供断言。线程安全(`breadcrumb`/`failure` 从 actor 上下文
/// 触发),用锁保护缓冲区 —— 同 `AuthServiceTests.FakeBackend` 的 `@unchecked
/// Sendable` 模式。
final class SpyDiagnostics: Diagnostics, @unchecked Sendable {
    struct Call: Equatable {
        let name: String
        let tags: [String: String]
        /// 失败调用的错误类名;breadcrumb / nil-error 失败为 nil。
        let errorClass: String?
    }

    /// 一条结构化日志:级别 + 消息 + 属性(都来自 `measure`/`failure` 自动派生)。
    struct LogCall: Equatable {
        let level: DiagnosticLevel
        let message: String
        let tags: [String: String]
    }

    /// 一次计数指标(count):key + 增量 + 低基数属性。
    struct CountCall: Equatable {
        let key: String
        let value: UInt
        let tags: [String: String]
    }

    /// 一次分布指标(distribution):key + 数值 + 单位 + 低基数属性。
    struct DistributionCall: Equatable {
        let key: String
        let value: Double
        let unit: DiagnosticUnit
        let tags: [String: String]
    }

    /// 一次瞬时量指标(gauge):key + 数值 + 单位 + 低基数属性。
    struct GaugeCall: Equatable {
        let key: String
        let value: Double
        let unit: DiagnosticUnit
        let tags: [String: String]
    }

    private let lock = NSLock()
    private var _breadcrumbs: [Call] = []
    private var _failures: [Call] = []
    private var _logs: [LogCall] = []
    private var _counts: [CountCall] = []
    private var _distributions: [DistributionCall] = []
    private var _gauges: [GaugeCall] = []

    var breadcrumbs: [Call] { lock.withLock { _breadcrumbs } }
    var failures: [Call] { lock.withLock { _failures } }
    var logs: [LogCall] { lock.withLock { _logs } }
    var counts: [CountCall] { lock.withLock { _counts } }
    var distributions: [DistributionCall] { lock.withLock { _distributions } }
    var gauges: [GaugeCall] { lock.withLock { _gauges } }
    var breadcrumbNames: [String] { breadcrumbs.map(\.name) }
    var failureNames: [String] { failures.map(\.name) }
    var countKeys: [String] { counts.map(\.key) }
    var distributionKeys: [String] { distributions.map(\.key) }
    var gaugeKeys: [String] { gauges.map(\.key) }

    func breadcrumb(_ name: String, _ tags: [String: String]) {
        lock.withLock { _breadcrumbs.append(Call(name: name, tags: tags, errorClass: nil)) }
    }

    func failure(_ name: String, error: Error?, _ tags: [String: String]) {
        let klass = error.map(diagnosticErrorClass)
        lock.withLock { _failures.append(Call(name: name, tags: tags, errorClass: klass)) }
    }

    func log(_ level: DiagnosticLevel, _ message: String, _ tags: [String: String]) {
        lock.withLock { _logs.append(LogCall(level: level, message: message, tags: tags)) }
    }

    func count(_ key: String, by value: UInt, _ tags: [String: String]) {
        lock.withLock { _counts.append(CountCall(key: key, value: value, tags: tags)) }
    }

    func distribution(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        lock.withLock { _distributions.append(DistributionCall(key: key, value: value, unit: unit, tags: tags)) }
    }

    func gauge(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {
        lock.withLock { _gauges.append(GaugeCall(key: key, value: value, unit: unit, tags: tags)) }
    }
}
