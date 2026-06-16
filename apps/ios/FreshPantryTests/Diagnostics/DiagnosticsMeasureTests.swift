import Foundation
import Testing
@testable import FreshPantry

/// `Diagnostics.measure` 默认实现的行为:成功/失败两路各发什么、是否透传错误。
struct DiagnosticsMeasureTests {
    private struct Boom: Error {}

    @Test func measureSuccessEmitsStartAndOkBreadcrumbs() async throws {
        let spy = SpyDiagnostics()
        let value = try await spy.measure("scan.lookup", ["source": "off"]) { 42 }

        #expect(value == 42)
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failures.isEmpty)
        let ok = spy.breadcrumbs.last!
        #expect(ok.tags["outcome"] == "ok")
        #expect(ok.tags["source"] == "off")
        #expect(ok.tags["durationMs"] != nil)
    }

    @Test func measureFailureRethrowsAndRecordsFailure() async {
        let spy = SpyDiagnostics()
        await #expect(throws: Boom.self) {
            try await spy.measure("scan.lookup", ["source": "off"]) { throw Boom() }
        }

        // 失败路径:start + 一条带 outcome=fail 的 breadcrumb,外加一条 failure。
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failureNames == ["scan.lookup"])
        let f = spy.failures.first!
        #expect(f.tags["outcome"] == "fail")
        #expect(f.tags["errorClass"] == "Boom")
        #expect(f.errorClass == "Boom")
        // 失败路径最后一条 breadcrumb 断言。
        let last = spy.breadcrumbs.last!
        #expect(last.tags["outcome"] == "fail")
        #expect(last.tags["errorClass"] == "Boom")
        #expect(last.tags["durationMs"] != nil)
        #expect(last.tags["source"] == "off")
    }

    // MARK: - 自动派生的指标 + 日志(facade auto-derive)

    @Test func measureSuccessEmitsDistributionCountAndLog() async throws {
        let spy = SpyDiagnostics()
        _ = try await spy.measure("scan.lookup", ["source": "off"]) { 42 }

        // 恰好一条分布:`<name>.duration`,毫秒单位,value>0,低基数属性带 outcome=ok。
        #expect(spy.distributions.count == 1)
        let dist = spy.distributions.first!
        #expect(dist.key == "scan.lookup.duration")
        #expect(dist.unit == .milliseconds)
        #expect(dist.value >= 0)
        #expect(dist.tags["outcome"] == "ok")
        #expect(dist.tags["source"] == "off")
        // durationMs 是分布的 VALUE,绝不进指标属性(高基数)。
        #expect(dist.tags["durationMs"] == nil)

        // 恰好一条计数:`<name>`,+1,属性带 outcome=ok,无 durationMs。
        #expect(spy.counts.count == 1)
        let count = spy.counts.first!
        #expect(count.key == "scan.lookup")
        #expect(count.value == 1)
        #expect(count.tags["outcome"] == "ok")
        #expect(count.tags["durationMs"] == nil)

        // 恰好一条 .info 日志:消息=name,日志属性可带 durationMs(日志不聚合)。
        #expect(spy.logs.count == 1)
        let log = spy.logs.first!
        #expect(log.level == .info)
        #expect(log.message == "scan.lookup")
        #expect(log.tags["outcome"] == "ok")
        #expect(log.tags["source"] == "off")
        #expect(log.tags["durationMs"] != nil)
    }

    @Test func measureFailureEmitsDistributionAndCountWithErrorClass() async {
        let spy = SpyDiagnostics()
        await #expect(throws: Boom.self) {
            try await spy.measure("scan.lookup", ["source": "off"]) { throw Boom() }
        }

        // 失败路径分布:outcome=fail + errorClass,无 durationMs 属性。
        #expect(spy.distributions.count == 1)
        let dist = spy.distributions.first!
        #expect(dist.key == "scan.lookup.duration")
        #expect(dist.unit == .milliseconds)
        #expect(dist.tags["outcome"] == "fail")
        #expect(dist.tags["errorClass"] == "Boom")
        #expect(dist.tags["source"] == "off")
        #expect(dist.tags["durationMs"] == nil)

        // 失败路径计数:outcome=fail + errorClass。
        #expect(spy.counts.count == 1)
        let count = spy.counts.first!
        #expect(count.key == "scan.lookup")
        #expect(count.value == 1)
        #expect(count.tags["outcome"] == "fail")
        #expect(count.tags["errorClass"] == "Boom")

        // 失败路径不另发 .info 日志 —— 错误日志由 failure() 集中负责(见 SentryDiagnostics)。
        #expect(spy.logs.isEmpty)
        // 仍然记录 failure 并透传错误(由上面的 throws 断言覆盖)。
        #expect(spy.failureNames == ["scan.lookup"])
    }
}

/// SDK 无关的诊断枚举(级别/单位)的轻量行为断言 —— 它们必须可比较,以便 Spy/
/// 断言能精确匹配。
struct DiagnosticEnumTests {
    @Test func unitEquatableDistinguishesGeneric() {
        #expect(DiagnosticUnit.milliseconds == DiagnosticUnit.milliseconds)
        #expect(DiagnosticUnit.bytes != DiagnosticUnit.none)
        #expect(DiagnosticUnit.generic("frames") == DiagnosticUnit.generic("frames"))
        #expect(DiagnosticUnit.generic("frames") != DiagnosticUnit.generic("items"))
    }

    @Test func levelCasesAreDistinct() {
        let all: [DiagnosticLevel] = [.debug, .info, .warning, .error]
        // 四个级别值彼此可区分(Spy 的 LogCall 依赖其 Equatable)。
        #expect(Set(all.map { String(describing: $0) }).count == 4)
    }
}
