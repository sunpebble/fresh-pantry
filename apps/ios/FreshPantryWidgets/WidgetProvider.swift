import WidgetKit

/// 一条时间线条目:渲染时刻 + 选中内容 + 四类快照合集。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetContentChoice
    let bundle: WidgetSnapshotBundle
    /// App Group 里还没有 app 发布的快照(用户尚未启动过 app)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

struct WidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: .expiring, bundle: .empty, needsAppLaunch: false)
    }

    func snapshot(for configuration: SelectWidgetContentIntent, in context: Context) async -> WidgetEntry {
        entry(for: configuration.content, now: .now)
    }

    func timeline(for configuration: SelectWidgetContentIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date.now
        let current = entry(for: configuration.content, now: now)
        // 下次刷新:跨午夜(临期剩余天数每天重算)。app 在数据变更时另会显式 reload。
        let nextMidnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(6 * 3600)
        return Timeline(entries: [current], policy: .after(nextMidnight))
    }

    /// **只读** App Group 里 app 预算好的快照——widget 进程从不打开 SwiftData
    /// 容器(其内存预算约 30MB,开 13 模型容器 + 取数会被 jetsam 杀,组件停在占位)。
    /// 快照尚未发布(app 未首启)→ needsAppLaunch。
    private func entry(for content: WidgetContentChoice, now: Date) -> WidgetEntry {
        guard let bundle = WidgetSnapshotStore.read() else {
            return WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)
        }
        return WidgetEntry(date: now, content: content, bundle: bundle, needsAppLaunch: false)
    }
}
