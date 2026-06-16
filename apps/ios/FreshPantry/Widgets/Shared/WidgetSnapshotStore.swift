import Foundation

/// 跨进程小组件快照通道。**app 侧**预算出四类快照(内存充足)写进 App Group
/// 容器的一份小 JSON;**widget 时间线侧**只读这一小份、从不在 widget 进程里打开
/// SwiftData 容器。
///
/// 缘由:widget 扩展的时间线 provider 内存预算极紧(约 30MB),打开 13 个 @Model
/// 的 SwiftData 容器 + 取数会被系统 jetsam 杀掉 / 在跨进程打开时崩溃,导致组件
/// 永远停在 redaction 占位渲染不出内容。把取数搬到 app、widget 只读标量快照,是
/// Apple 对 widget「时间线要轻」的官方做法,且对内存/崩溃/并发各成因通杀。
enum WidgetSnapshotStore {
    private static let fileName = "widget-snapshot.json"

    /// App Group 容器内快照文件 URL;App Group 未授权(本地未签名 dev)时为 nil。
    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharedDefaults.appGroupID)?
            .appending(path: fileName)
    }

    /// **app 侧**:原子写入最新四类快照。失败容忍——下次刷新重试,widget 退回
    /// 旧值 / 占位,绝不因一次写失败崩溃。
    static func write(_ bundle: WidgetSnapshotBundle) {
        guard let url = fileURL(), let data = try? JSONEncoder().encode(bundle) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// **widget 侧**:读已写入的快照。不存在(app 尚未首次发布)/ 损坏 → nil,
    /// 调用方据此显示 needsAppLaunch 占位。纯文件读,无 SwiftData。
    static func read() -> WidgetSnapshotBundle? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshotBundle.self, from: data)
    }

    /// **widget 交互勾选后**就地翻转某购物项的 `isChecked`(无需重开 store 重算),
    /// 让 `reloadAllTimelines()` 后立即反映新状态;真正的 store 写 + outbox 由
    /// `ShoppingToggleService` 负责,app 下次刷新会用权威数据覆盖本快照。
    /// 目标项不在快照内(超出展示上限)→ no-op(store 仍已翻转,app 刷新后对齐)。
    static func toggleShoppingItem(itemID: String) {
        guard let bundle = read() else { return }
        write(togglingShoppingItem(in: bundle, itemID: itemID))
    }

    /// 纯变换(可单测,不碰文件):翻转 `itemID` 那项的勾选,并相应 ±1 调整
    /// `uncheckedCount`;目标项不存在 → 原样返回。
    static func togglingShoppingItem(in bundle: WidgetSnapshotBundle, itemID: String) -> WidgetSnapshotBundle {
        var delta = 0
        let items = bundle.shopping.items.map { item -> WidgetShoppingSnapshot.Item in
            guard item.id == itemID else { return item }
            let newChecked = !item.isChecked
            delta = newChecked ? -1 : 1  // 未勾选→勾选:待买少一件
            return WidgetShoppingSnapshot.Item(id: item.id, name: item.name, isChecked: newChecked)
        }
        guard delta != 0 else { return bundle }
        var result = bundle
        result.shopping = WidgetShoppingSnapshot(
            uncheckedCount: max(0, bundle.shopping.uncheckedCount + delta),
            items: items
        )
        return result
    }
}
