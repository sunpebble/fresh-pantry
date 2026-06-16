import SwiftUI
import WidgetKit

/// accessoryCircular:临期件数环。
struct AccessoryCircularView: View {
    let snapshot: WidgetExpiringSnapshot
    var body: some View {
        Gauge(value: Double(min(snapshot.needsAttentionCount, 9)), in: 0...9) {
            Image(systemName: "exclamationmark.triangle")
        } currentValueLabel: {
            Text("\(snapshot.needsAttentionCount)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(URL(string: "freshpantry://expiring"))
    }
}

/// accessoryRectangular:可配置内容的一行摘要。
struct AccessoryRectangularView: View {
    let entry: WidgetEntry
    let content: WidgetContentChoice
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch content {
            case .expiring:
                Label("临期 \(entry.bundle.expiring.needsAttentionCount) 件", systemImage: "exclamationmark.triangle")
                if let first = entry.bundle.expiring.items.first {
                    Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .mealPlan:
                Label("今日 \(entry.bundle.mealPlan.items.count) 顿", systemImage: "fork.knife")
                if let first = entry.bundle.mealPlan.items.first {
                    Text(first.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .shopping:
                Label("待买 \(entry.bundle.shopping.uncheckedCount) 项", systemImage: "cart")
            case .waste:
                Label("用掉率 \(entry.bundle.waste.useUpPercent)%", systemImage: "leaf")
            }
        }
        .widgetURL(URL(string: contentDeepLink(content)))
    }
}

/// accessoryInline:临期一句话。
struct AccessoryInlineView: View {
    let snapshot: WidgetExpiringSnapshot
    var body: some View {
        Text("临期 \(snapshot.needsAttentionCount) 件")
            .widgetURL(URL(string: "freshpantry://expiring"))
    }
}

func contentDeepLink(_ content: WidgetContentChoice) -> String {
    switch content {
    case .expiring: return "freshpantry://expiring"
    case .mealPlan: return "freshpantry://mealplan"
    case .shopping: return "freshpantry://shopping"
    case .waste: return "freshpantry://waste"
    }
}
