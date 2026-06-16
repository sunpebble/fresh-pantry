import Foundation

/// 小组件深链路由(app 端)。`freshpantry://<host>` → 内容目标。临期/今日膳食/
/// 减废三屏由首页 `DashboardRoute` push;购物切到购物 tab。与 invite / recipe
/// import 的 capture 互斥:只认下面四个固定 host,其余 URL `capture` 返回 false,
/// 让 `onOpenURL` 继续交给其它 router。
@Observable
@MainActor
final class WidgetDeepLinkRouter {
    enum Destination: Hashable, Sendable {
        case expiring, mealPlan, shopping, waste
    }

    private(set) var pending: Destination?

    /// 纯解析:已知 host → 目标,否则 nil。不认 scheme 以外或带 query 的(如
    /// import-recipe)。
    static func destination(for url: URL) -> Destination? {
        guard url.scheme == "freshpantry" else { return nil }
        switch url.host() {
        case "expiring": return .expiring
        case "mealplan": return .mealPlan
        case "shopping": return .shopping
        case "waste": return .waste
        default: return nil
        }
    }

    /// 拦截本 router 拥有的 URL;命中则记 pending 返回 true,否则不动返回 false。
    @discardableResult
    func capture(url: URL) -> Bool {
        guard let dest = Self.destination(for: url) else { return false }
        pending = dest
        return true
    }

    @discardableResult
    func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }

    func clear() { pending = nil }
}
