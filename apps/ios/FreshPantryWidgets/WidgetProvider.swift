import WidgetKit

/// 一条时间线条目:渲染时刻 + 四类快照合集。内容类别由各 widget 固定(见
/// `FreshPantryWidget.swift` 的 4 个 StaticConfiguration),不再由 entry 携带。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let bundle: WidgetSnapshotBundle
    /// App Group 里还没有 app 发布的快照(用户尚未启动过 app)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

/// 普通 `TimelineProvider`(非 App Intent 配置)。**只读** App Group 里 app 预算好
/// 的快照——不在 widget 进程碰 SwiftData。所有固定 widget 共用本 provider。
///
/// 刻意不用 `AppIntentConfiguration` + 配置 intent:真机 Release 包不认该配置
/// intent(长按无「编辑小组件」),导致单个可配置 widget 卡在默认内容。改为每类
/// 内容一个独立 StaticConfiguration widget,零配置依赖,真机稳定可用。
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, bundle: .empty, needsAppLaunch: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeEntry(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date.now
        // 下次刷新跨午夜(临期剩余天数每天重算);app 在数据变更时另会显式 reload。
        let nextMidnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [makeEntry(now: now)], policy: .after(nextMidnight)))
    }

    private func makeEntry(now: Date) -> WidgetEntry {
        guard let bundle = WidgetSnapshotStore.read() else {
            return WidgetEntry(date: now, bundle: .empty, needsAppLaunch: true)
        }
        return WidgetEntry(date: now, bundle: bundle, needsAppLaunch: false)
    }
}
