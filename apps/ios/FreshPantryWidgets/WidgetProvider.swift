import AppIntents
import WidgetKit

/// 一条时间线条目:渲染时刻 + 内容类别 + 四类快照合集。内容类别来源:固定 widget
/// 由其 `SnapshotProvider(content:)` 注入;可配置 widget 由 `SelectWidgetContentIntent`
/// 注入。视图统一读 `entry.content`。
struct WidgetEntry: TimelineEntry {
    let date: Date
    let content: WidgetContentChoice
    let bundle: WidgetSnapshotBundle
    /// App Group 里还没有 app 发布的快照(用户尚未启动过 app)→ 显示「打开 app」占位。
    let needsAppLaunch: Bool
}

/// 共享取数:**只读** App Group 里 app 预算好的快照——不在 widget 进程碰 SwiftData。
/// 临期快照存的是候选集,这里按条目渲染时刻 `date` 投影出天数/分桶/计数/排序
/// (`projected(now:)`,纯日期数学,不碰 30MB 内存红线)。
private func makeWidgetEntry(content: WidgetContentChoice, bundle: WidgetSnapshotBundle, date: Date) -> WidgetEntry {
    var projected = bundle
    projected.expiring = bundle.expiring.projected(now: date)
    return WidgetEntry(date: date, content: content, bundle: projected, needsAppLaunch: false)
}

private func makeWidgetSnapshot(content: WidgetContentChoice, now: Date) -> WidgetEntry {
    guard let bundle = WidgetSnapshotStore.read() else {
        return WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)
    }
    return makeWidgetEntry(content: content, bundle: bundle, date: now)
}

/// 时间线:当前时刻一条 + 未来几个午夜各一条,每条按其时刻重投影临期天数——
/// 系统迟迟不给 reload 窗口时,已烘焙的条目也会让「还剩 N 天」逐日推进、过期项
/// 如期计入。跨第一个午夜后照常整线重建(读到 app 可能重发的新快照)。膳食/减废
/// 快照不随条目变化(重算需取数,widget 进程不做),由 app 发布覆盖,与既有行为一致。
private func makeWidgetTimeline(content: WidgetContentChoice, now: Date) -> Timeline<WidgetEntry> {
    guard let bundle = WidgetSnapshotStore.read() else {
        return Timeline(
            entries: [WidgetEntry(date: now, content: content, bundle: .empty, needsAppLaunch: true)],
            policy: .after(nextWidgetReload(after: now))
        )
    }
    var dates = [now]
    for _ in 0..<3 { dates.append(nextWidgetReload(after: dates[dates.count - 1])) }
    let entries = dates.map { makeWidgetEntry(content: content, bundle: bundle, date: $0) }
    return Timeline(entries: entries, policy: .after(dates[1]))
}

/// 下次刷新:跨午夜(临期天数按新的一天重投影);app 在数据变更时另会显式 reload。
private func nextWidgetReload(after now: Date) -> Date {
    Calendar.current.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
    ) ?? now.addingTimeInterval(6 * 3600)
}

/// 固定 widget 的 provider(普通 `TimelineProvider`,内容类别由实例固定)。
/// 每个固定 widget 用 `SnapshotProvider(content: .shopping)` 等注入自己那类。
struct SnapshotProvider: TimelineProvider {
    let content: WidgetContentChoice

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: content, bundle: .empty, needsAppLaunch: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeWidgetSnapshot(content: content, now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        completion(makeWidgetTimeline(content: content, now: .now))
    }
}

/// 可配置 widget 的 provider(`AppIntentTimelineProvider`,内容类别来自配置 intent)。
/// ⚠️ 真机 Release 是否认该配置待验证;作为「补充」与 4 个固定 widget 并存,
/// 即便不可配置也不影响固定 widget。
struct ConfigurableSnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, content: .expiring, bundle: .empty, needsAppLaunch: false)
    }

    func snapshot(for configuration: SelectWidgetContentIntent, in context: Context) async -> WidgetEntry {
        makeWidgetSnapshot(content: configuration.content, now: .now)
    }

    func timeline(for configuration: SelectWidgetContentIntent, in context: Context) async -> Timeline<WidgetEntry> {
        makeWidgetTimeline(content: configuration.content, now: .now)
    }
}
