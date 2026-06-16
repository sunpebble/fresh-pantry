import Foundation

/// 结构化日志级别 —— 故意 SDK 无关(不引 Sentry),好让 OSLog/Spy/Noop 各自
/// 映射到自己的后端而无需依赖 sentry-cocoa。仅 `SentryDiagnostics` 把它翻译成
/// `SentrySDK.logger` 的 trace/debug/info/warn/error/fatal。
enum DiagnosticLevel: Sendable, Equatable {
    case debug, info, warning, error
}

/// 指标单位 —— 同样 SDK 无关。`measure` 用 `.milliseconds` 计时;`.none` 表示无量纲
/// (映射到 SDK 的 `nil`),`.generic(_)` 透传自定义单位字符串。仅 `SentryDiagnostics`
/// 把它翻译成 `SentryUnit`。
enum DiagnosticUnit: Sendable, Equatable {
    case milliseconds, bytes, none, generic(String)
}

/// 所有被埋点接缝唯一编程对象的诊断门面。三个原语;`measure` 是共享默认实现
/// (见下),所以具体 sink 只需实现 `breadcrumb` + `failure`。
///
/// 结构化日志(`log`)与指标(`count`/`distribution`/`gauge`)是新增原语:它们在
/// `extension Diagnostics` 里有默认 no-op 实现,所以 `NoopDiagnostics` 及任何旧
/// 实现零改动即可继续编译;只有 Sentry/OSLog/Spy 重写它们。`measure` 默认实现会
/// 自动从计时结果派生这些指标 + 一条日志,**不在别处新增埋点调用点**。
///
/// 不变量:任何方法都不得因自身逻辑抛错、不得影响 app 行为。`measure` 仅透传
/// (rethrow)被包裹 `work` 的错误;其余原语内部吞掉一切。诊断的 bug 绝不能搞挂
/// 功能。低基数纪律:只有低基数维度(outcome、errorClass、调用方既有 tag)能进
/// 指标属性;原始错误 message 与高基数的 durationMs 绝不进指标属性。
protocol Diagnostics: Sendable {
    /// 操作轨迹 —— 留一条 Sentry breadcrumb,本身从不上报。`tags` 为低基数、
    /// 非 PII 维度(entityType、source、outcome…)。
    ///
    /// - Note: `outcome`/`durationMs`/`errorClass` 由 `measure` 自动注入,
    ///   `diagnostic` 由 Sentry sink 作为保留 key 写入;调用方不应在 `tags` 里
    ///   传这些 key,否则可能被覆盖或产生歧义。
    func breadcrumb(_ name: String, _ tags: [String: String])

    /// 一次失败 → 一条 Sentry 事件(level=.error),按 `name` + 错误类名做
    /// fingerprint,使同一失败聚合成一个 issue。`error` 对从未 throw 的逻辑
    /// 失败(如同步 strike)为 nil。Sentry sink 会同时把失败镜像到 Logs+Metrics
    /// (见 `SentryDiagnostics.failure`),所以非 `measure` 的直接失败也能进可观测。
    func failure(_ name: String, error: Error?, _ tags: [String: String])

    /// 一条结构化日志 —— 进 Sentry Logs(非 issue)。`tags` 作为日志属性;与指标
    /// 属性不同,日志不做聚合,故可携带 `durationMs` 这类较高基数的维度。默认
    /// no-op(见扩展),仅 Sentry/OSLog/Spy 重写。
    func log(_ level: DiagnosticLevel, _ message: String, _ tags: [String: String])

    /// 计数指标(counter)—— 给 `key` 累加 `value`(默认 1)。`tags` 必须低基数
    /// (会成为指标属性维度,高基数会爆维度)。默认 no-op。
    func count(_ key: String, by value: UInt, _ tags: [String: String])

    /// 分布指标(distribution)—— 记录一个数值样本以做统计分析(均值/分位数)。
    /// `value` 本身是被测量(如毫秒耗时),`unit` 标注量纲。`tags` 必须低基数;
    /// 测量值绝不进 `tags`(否则爆维度)。默认 no-op。
    func distribution(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String])

    /// 瞬时量指标(gauge)—— 记录某时刻的当前状态值(如队列深度、内存占用),
    /// 可升可降。`tags` 必须低基数。默认 no-op。
    func gauge(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String])
}

extension Diagnostics {
    /// 默认 no-op:新增的日志/指标原语对未重写的 sink(如 `NoopDiagnostics`)
    /// 一律静默。在协议体里声明 + 这里给默认值,既保证旧实现零改动编译,又保留
    /// 动态派发(Sentry/OSLog/Spy 的重写会被正确调用)。
    func log(_ level: DiagnosticLevel, _ message: String, _ tags: [String: String]) {}
    func count(_ key: String, by value: UInt, _ tags: [String: String]) {}
    func distribution(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {}
    func gauge(_ key: String, _ value: Double, unit: DiagnosticUnit, _ tags: [String: String]) {}

    /// 给一次异步操作计时:先发 `<name>.start` breadcrumb,成功则发 `<name>`
    /// breadcrumb 带 `outcome=ok` + `durationMs`,失败则发 `failure(<name>)` 带
    /// `outcome=fail` + `errorClass`(耗时进 breadcrumb,绝不进 Sentry tag —— 高
    /// 基数)。透明 rethrow 底层错误。
    ///
    /// 在保持上述 breadcrumb 序列**逐字节不变**的前提下,自动派生指标 + 日志:
    /// - 成功:`distribution("<name>.duration", ms, .milliseconds, [tags+outcome:ok])`
    ///   + `count("<name>", 1, [tags+outcome:ok])` + 一条 `.info` 日志(日志属性
    ///   额外带 `durationMs`)。
    /// - 失败:`distribution` + `count` 带 `outcome:fail` + `errorClass`,随后调用
    ///   `failure(...)`(由它集中负责错误日志,这里不另发日志)。
    ///   指标属性始终低基数(outcome / errorClass / 调用方既有 tag);`durationMs`
    ///   是分布的 VALUE,绝不进任何指标属性。
    func measure<T>(
        _ name: String,
        _ tags: [String: String] = [:],
        _ work: () async throws -> T
    ) async throws -> T {
        let clock = ContinuousClock()
        let started = clock.now
        breadcrumb("\(name).start", tags)
        do {
            let result = try await work()
            let ms = Self.millis(from: started, clock: clock)
            var ok = tags
            ok["outcome"] = "ok"
            ok["durationMs"] = Self.format(millis: ms)
            breadcrumb(name, ok)

            // 自动派生:指标属性低基数(不含 durationMs);日志属性可含 durationMs。
            var metricTags = tags
            metricTags["outcome"] = "ok"
            distribution("\(name).duration", ms, unit: .milliseconds, metricTags)
            count(name, by: 1, metricTags)
            log(.info, name, ok)
            return result
        } catch {
            let ms = Self.millis(from: started, clock: clock)
            var failed = tags
            failed["outcome"] = "fail"
            failed["errorClass"] = diagnosticErrorClass(error)
            var crumb = failed
            crumb["durationMs"] = Self.format(millis: ms)
            breadcrumb(name, crumb)

            // 自动派生:失败维度(outcome=fail + errorClass)进指标,durationMs 不进。
            distribution("\(name).duration", ms, unit: .milliseconds, failed)
            count(name, by: 1, failed)
            // 错误日志由 failure() 集中负责(它同时镜像到 Logs+Metrics),这里不另发。
            failure(name, error: error, failed)
            throw error
        }
    }

    /// 自 `started` 起的毫秒数(Double),经 `Duration.components` 计算(避免
    /// `Duration` 相除的不确定性)。既作分布指标的 VALUE,也供 `format(millis:)`
    /// 渲染成 breadcrumb/日志里的字符串。
    private static func millis(from started: ContinuousClock.Instant, clock: ContinuousClock) -> Double {
        let comps = (clock.now - started).components
        let ms = comps.seconds * 1000 + comps.attoseconds / 1_000_000_000_000_000
        return Double(ms)
    }

    /// 把毫秒数渲染成 breadcrumb/日志属性用的整数字符串(与历史格式逐字节一致)。
    private static func format(millis: Double) -> String {
        String(Int64(millis))
    }
}

/// 错误的类型名 —— 一个可安全用作 Sentry tag 的低基数类别标签(原始错误
/// message 可能含用户数据,从不用作 tag)。
func diagnosticErrorClass(_ error: Error) -> String {
    String(describing: type(of: error))
}

/// 默认 sink:什么都不做。所有 service 构造器的默认值,保证未接线的代码路径
/// 与全部现有测试行为完全不变。`measure` 由协议扩展提供(仍正确计时并透传),
/// 新增的 `log`/`count`/`distribution`/`gauge` 由协议扩展的默认 no-op 覆盖,
/// 故此处无需声明。
struct NoopDiagnostics: Diagnostics {
    func breadcrumb(_ name: String, _ tags: [String: String]) {}
    func failure(_ name: String, error: Error?, _ tags: [String: String]) {}
}
