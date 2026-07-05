import SwiftUI
import WidgetKit

/// 所有 widget 共用根视图:内容类别读 `entry.content`(固定 widget 由其 provider
/// 固定,可配置 widget 由配置 intent 决定)。系统尺寸走对应内容视图;锁屏配件
/// (circular/rectangular/inline)也按 `entry.content` 渲染各自摘要。
struct WidgetRootView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.needsAppLaunch {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("widget.launch.openApp").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            contentView
        }
    }

    @ViewBuilder private var contentView: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            switch entry.content {
            case .expiring: ExpiringWidgetView(snapshot: entry.bundle.expiring, family: family)
            case .mealPlan: MealPlanWidgetView(snapshot: entry.bundle.mealPlan, family: family)
            case .shopping: ShoppingWidgetView(snapshot: entry.bundle.shopping, family: family)
            case .waste: WasteWidgetView(snapshot: entry.bundle.waste, family: family)
            }
        }
    }
}
