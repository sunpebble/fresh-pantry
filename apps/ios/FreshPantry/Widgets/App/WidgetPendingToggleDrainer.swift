import Foundation

extension Notification.Name {
    /// Posted by `WidgetPendingToggleDrainer` after a drain actually FLIPPED a
    /// row — the foreground 购物 list (and the 首页 购物 tile) are DIFFERENT
    /// `ShoppingStore` instances that know nothing of this cross-process write,
    /// so without the pulse they keep showing their pre-toggle snapshot until a
    /// manual pull / household switch / remote-sync apply (the exact mirror of
    /// `.intentDidDrainShoppingAdd`).
    static let widgetDidDrainShoppingToggle = Notification.Name("fresh_pantry.widget.didDrainShoppingToggle")
}

/// **app 侧**:把 widget 攒下的「待落库勾选」真正落库。widget 进程只 append 了
/// itemID 到 App Group 队列(不碰 SwiftData);这里在主进程经 `ShoppingToggleService`
/// 逐条翻转 store + 记 outbox,再用权威数据重写展示快照(覆盖 widget 的乐观补丁)。
/// 在启动/家庭就绪/回前台时调用,与 `IntentAddDrainer` 同位。
enum WidgetPendingToggleDrainer {
    /// `pending` defaults to draining (read + clear) the App Group queue — the
    /// production behavior; tests inject an explicit list so they never touch the
    /// shared cross-process file (mirrors `IntentAddDrainer`'s injected queue).
    /// `center` is injectable for the same reason its sibling drainer's is.
    static func drain(
        dependencies: AppDependencies,
        pending: [String] = WidgetPendingToggleStore.drain(),
        center: NotificationCenter = .default
    ) async {
        guard !pending.isEmpty else { return }
        var didWrite = false
        for id in pending {
            if await ShoppingToggleService.toggle(
                container: dependencies.modelContainer,
                householdID: dependencies.householdID,
                itemID: id,
                clientID: dependencies.syncSession.clientId,
                now: .now
            ) {
                didWrite = true
            }
        }
        await WidgetSnapshotPublisher.publish(
            container: dependencies.modelContainer,
            householdID: dependencies.householdID
        )
        // Pulse only on a real flip — a drain that matched no row (the queued item
        // was deleted before foreground) changed nothing, so the visible list has
        // nothing new to show and a reload would be wasted work.
        if didWrite {
            center.post(name: .widgetDidDrainShoppingToggle, object: nil)
        }
    }
}
