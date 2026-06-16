import AppIntents
import WidgetKit

/// widget 内勾选购物项。运行在 widget 进程:翻转共享 store + 记 outbox(经
/// `ShoppingToggleService`),再重载时间线让勾选即时反映。
struct ToggleShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "勾选购物项" }

    @Parameter(title: "itemID")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        guard let container = ModelContainerFactory.makeSharedExisting() else { return .result() }
        let householdID = WidgetSharedDefaults.readHouseholdID()
        let clientID = WidgetSharedDefaults.readClientID()
        let toggled = await ShoppingToggleService.toggle(
            container: container, householdID: householdID, itemID: itemID, clientID: clientID, now: .now
        )
        // store 已翻转 → 就地补丁预算快照,使重载后立即反映新勾选(app 下次刷新
        // 会用权威数据覆盖)。读路径只读这份快照,不再开 SwiftData。
        if toggled { WidgetSnapshotStore.toggleShoppingItem(itemID: itemID) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
