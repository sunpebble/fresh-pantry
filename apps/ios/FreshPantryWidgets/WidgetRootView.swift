import SwiftUI
import WidgetKit

/// 固定 widget 的根视图:内容类别由所属 widget 传入(见 FreshPantryWidget.swift)。
/// 锁屏 circular / inline 恒显示临期;rectangular 显示本 widget 的内容。
struct StaticWidgetRootView: View {
    let entry: WidgetEntry
    let content: WidgetContentChoice
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.needsAppLaunch {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("打开 Fresh Pantry").font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            contentView
        }
    }

    @ViewBuilder private var contentView: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(snapshot: entry.bundle.expiring)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry, content: content)
        case .accessoryInline:
            AccessoryInlineView(snapshot: entry.bundle.expiring)
        default:
            switch content {
            case .expiring: ExpiringWidgetView(snapshot: entry.bundle.expiring, family: family)
            case .mealPlan: MealPlanWidgetView(snapshot: entry.bundle.mealPlan, family: family)
            case .shopping: ShoppingWidgetView(snapshot: entry.bundle.shopping, family: family)
            case .waste: WasteWidgetView(snapshot: entry.bundle.waste, family: family)
            }
        }
    }
}
