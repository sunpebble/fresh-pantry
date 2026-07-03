import AppIntents

/// widget 内勾选购物项。`openAppWhenRun=NO`,由 chronod 在**主 app 进程**(app 运行/可唤醒
/// 时)后台执行,**刻意不碰 SwiftData**:perform 可能在受限的后台上下文跑,只做两件轻活
/// ① 记一条待落库翻转到 App Group 队列;② 就地补丁展示快照让重载后即时反映。app 下次前台
/// 经 `WidgetPendingToggleDrainer`→`ShoppingToggleService` 把队列真正落库 + 推送 outbox。
///
/// ⚠️ 此源文件须经 **dual-target membership** 同时编进 app + widget 两个 target(见
/// project.yml),**不要收进 framework**:`openAppWhenRun=NO` 交互 intent 由 chronod 按主 app
/// bundle 的运行时 AppIntents 索引(linkd 安装时注册)、按 **identifier** 解析;framework 的
/// intent 在 release 下不被 linkd 注册进该索引(FB #425),真机恒报 "no metadata for
/// ToggleShoppingItemIntent in com.sunpebble.freshpantry"。app 模块 `FreshPantry.*` 与 widget
/// 模块 `FreshPantryWidgets.*` mangled 名不同但**不失配**(匹配按 identifier,各 bundle 自洽)。
public struct ToggleShoppingItemIntent: AppIntent {
    public static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    public var itemID: String

    public init() {}
    public init(itemID: String) { self.itemID = itemID }

    public func perform() async throws -> some IntentResult {
        WidgetPendingToggleStore.enqueue(itemID: itemID)
        WidgetSnapshotStore.toggleShoppingItem(itemID: itemID)
        // 不显式 WidgetCenter.reloadAllTimelines():交互 AppIntent 的 perform 完成后,
        // 系统会对该 widget 保证一次立即 reload,届时重读上面已就地补丁的快照即反映勾选;
        // 而从扩展进程显式 reload 在真机会被节流(FB13152293),冗余且不可靠。
        return .result()
    }
}
