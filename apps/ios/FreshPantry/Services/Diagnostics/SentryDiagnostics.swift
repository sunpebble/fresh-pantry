#if !DEBUG
import Foundation
import Sentry

/// 把诊断路由到 Sentry。仅在非 DEBUG 构建编译(与 `SentryBootstrap` 一致 ——
/// 它同样 `#if !DEBUG` 包裹每个 Sentry 调用)。假定 `SentryBootstrap.start` 已
/// 启动 SDK;若未启动,这些调用在 sentry-cocoa 内部是无害 no-op。
///
/// API 形态(sentry-cocoa 9.17):`Breadcrumb(level:category:)` + `.message`/
/// `.data`、`SentrySDK.addBreadcrumb`、`SentrySDK.capture(error:block:)` 带
/// `Scope.setTag`/`fingerprint`、`Event(level:)` + `SentryMessage(formatted:)` +
/// `.tags`/`.fingerprint` + `SentrySDK.capture(event:)`。
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
                scope.setTag(value: name, key: "diagnostic")
                for (key, value) in tags { scope.setTag(value: value, key: key) }
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
    }
}
#endif
