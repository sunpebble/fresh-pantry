import SwiftUI
import WidgetKit

// 4 个独立固定 widget(零配置依赖,真机稳定)+ 1 个可配置 widget(补充,真机可配置性待验证)。
// 每个都支持系统尺寸 + 锁屏配件(circular/rectangular/inline),配件按各自内容类别渲染。

private let allFamilies: [WidgetFamily] = [
    .systemSmall, .systemMedium, .systemLarge,
    .accessoryCircular, .accessoryRectangular, .accessoryInline,
]

struct ExpiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryExpiring", provider: SnapshotProvider(content: .expiring)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.config.expiring.name")
        .description("widget.config.expiring.description")
        .supportedFamilies(allFamilies)
    }
}

struct MealPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryMealPlan", provider: SnapshotProvider(content: .mealPlan)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.config.mealPlan.name")
        .description("widget.config.mealPlan.description")
        .supportedFamilies(allFamilies)
    }
}

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryShopping", provider: SnapshotProvider(content: .shopping)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.config.shopping.name")
        .description("widget.config.shopping.description")
        .supportedFamilies(allFamilies)
    }
}

struct WasteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryWaste", provider: SnapshotProvider(content: .waste)) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.config.waste.name")
        .description("widget.config.waste.description")
        .supportedFamilies(allFamilies)
    }
}

/// 补充:单个可配置 widget(长按「编辑小组件」切内容)。真机 Release 可配置性待验证;
/// 与上面 4 个固定 widget 并存,即便不可配置也不影响它们。
struct ConfigurableWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "FreshPantryConfigurable",
            intent: SelectWidgetContentIntent.self,
            provider: ConfigurableSnapshotProvider()
        ) { entry in
            WidgetRootView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.config.configurable.name")
        .description("widget.config.configurable.description")
        .supportedFamilies(allFamilies)
    }
}
