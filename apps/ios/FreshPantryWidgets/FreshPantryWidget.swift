import SwiftUI
import WidgetKit

// 每类内容一个独立 StaticConfiguration widget(零配置依赖,真机稳定)。
// 用户在 widget 库里直接挑要的那类添加;不再是单个「可配置」widget。

struct ExpiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryExpiring", provider: SnapshotProvider()) { entry in
            StaticWidgetRootView(entry: entry, content: .expiring)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("临期食材")
        .description("临期 / 过期食材一览")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct MealPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryMealPlan", provider: SnapshotProvider()) { entry in
            StaticWidgetRootView(entry: entry, content: .mealPlan)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日膳食")
        .description("今天要做的菜")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryShopping", provider: SnapshotProvider()) { entry in
            StaticWidgetRootView(entry: entry, content: .shopping)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("购物清单")
        .description("待买清单,可直接勾选")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct WasteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreshPantryWaste", provider: SnapshotProvider()) { entry in
            StaticWidgetRootView(entry: entry, content: .waste)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("减废成效")
        .description("用掉率与减废统计")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
