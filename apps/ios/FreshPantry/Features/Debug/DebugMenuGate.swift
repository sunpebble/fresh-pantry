import Foundation

/// UserDefaults backing 的隐藏调试菜单解锁状态。沿用 `AppearanceStore` KV 模板:
/// `@Observable @MainActor`、可注入 suite。持久化(key `debug_menu_unlocked_v1`)
/// 使测试者解锁一次后,调试菜单入口跨启动保留 —— 包括 TestFlight / 生产构建,
/// 因为这是运行期开关而非 `#if DEBUG` 守卫。设备本地:排除备份 / 家庭同步。
@Observable
@MainActor
final class DebugMenuGate {
    static let storageKey = "debug_menu_unlocked_v1"

    private let defaults: UserDefaults

    /// Settings 里是否显示隐藏的「调试菜单」入口。
    private(set) var isUnlocked: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isUnlocked = defaults.bool(forKey: Self.storageKey)
    }

    /// 显示调试菜单并持久化。
    func unlock() {
        isUnlocked = true
        defaults.set(true, forKey: Self.storageKey)
    }

    /// 重新隐藏调试菜单并持久化。
    func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Self.storageKey)
    }
}
