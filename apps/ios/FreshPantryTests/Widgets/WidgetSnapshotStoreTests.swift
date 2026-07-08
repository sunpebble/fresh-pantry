import Foundation
import Testing
@testable import FreshPantry

struct WidgetSnapshotStoreTests {
    private func sampleBundle() -> WidgetSnapshotBundle {
        WidgetSnapshotBundle(
            expiring: WidgetExpiringSnapshot(
                expiredCount: 2, urgentCount: 1, soonCount: 0,
                items: [.init(name: "牛奶", daysRemaining: -1,
                              expiryDate: Date(timeIntervalSince1970: 1_700_000_000),
                              lowFreshness: true)]
            ),
            mealPlan: WidgetMealPlanSnapshot(
                items: [.init(title: "番茄炒蛋", done: false)]
            ),
            shopping: WidgetShoppingSnapshot(
                uncheckedCount: 2,
                items: [
                    .init(id: "a", name: "鸡蛋", isChecked: false),
                    .init(id: "b", name: "盐", isChecked: false),
                    .init(id: "c", name: "酱油", isChecked: true),
                ]
            ),
            waste: WidgetWasteSnapshot(useUpPercent: 80, rescuedCount: 3, wastedCount: 2, isEmpty: false)
        )
    }

    // 跨进程通道靠 JSON 编解码:app 写、widget 读必须无损往返。
    @Test func bundleSurvivesCodableRoundTrip() throws {
        let original = sampleBundle()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshotBundle.self, from: data)
        #expect(decoded == original)
    }

    // 旧版快照 JSON(项上无 expiryDate/lowFreshness)必须仍可解码(升级后首刷读旧文件)。
    @Test func legacyExpiringItemJSONDecodes() throws {
        let json = Data(#"{"name":"牛奶","daysRemaining":-1}"#.utf8)
        let item = try JSONDecoder().decode(WidgetExpiringSnapshot.Item.self, from: json)
        #expect(item.daysRemaining == -1)
        #expect(item.expiryDate == nil)
        #expect(item.lowFreshness == nil)
    }

    @Test func emptyBundleRoundTrips() throws {
        let data = try JSONEncoder().encode(WidgetSnapshotBundle.empty)
        let decoded = try JSONDecoder().decode(WidgetSnapshotBundle.self, from: data)
        #expect(decoded == .empty)
    }

    // 交互勾选就地补丁:未勾选→勾选,待买计数 -1。
    @Test func togglingUncheckedItemChecksItAndDecrementsCount() {
        let patched = WidgetSnapshotStore.togglingShoppingItem(in: sampleBundle(), itemID: "a")
        #expect(patched.shopping.items.first { $0.id == "a" }?.isChecked == true)
        #expect(patched.shopping.uncheckedCount == 1)              // 2 → 1
        #expect(patched.shopping.items.first { $0.id == "b" }?.isChecked == false) // 其他项不动
    }

    // 已勾选→未勾选,待买计数 +1。
    @Test func togglingCheckedItemUnchecksItAndIncrementsCount() {
        let patched = WidgetSnapshotStore.togglingShoppingItem(in: sampleBundle(), itemID: "c")
        #expect(patched.shopping.items.first { $0.id == "c" }?.isChecked == false)
        #expect(patched.shopping.uncheckedCount == 3)              // 2 → 3
    }

    // 目标项不在快照内(超出展示上限)→ 原样返回(store 仍已翻转,app 刷新后对齐)。
    @Test func togglingUnknownItemIsNoOp() {
        let original = sampleBundle()
        let patched = WidgetSnapshotStore.togglingShoppingItem(in: original, itemID: "missing")
        #expect(patched == original)
    }

    // uncheckedCount 不会被压到负数。
    @Test func toggleCountNeverGoesNegative() {
        let bundle = WidgetSnapshotBundle(
            shopping: WidgetShoppingSnapshot(
                uncheckedCount: 0,
                items: [.init(id: "x", name: "葱", isChecked: false)]
            )
        )
        let patched = WidgetSnapshotStore.togglingShoppingItem(in: bundle, itemID: "x")
        #expect(patched.shopping.uncheckedCount == 0)
    }
}
