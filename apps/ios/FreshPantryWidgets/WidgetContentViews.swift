import SwiftUI
import WidgetKit

// MARK: 临期

struct ExpiringWidgetView: View {
    let snapshot: WidgetExpiringSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("临期 \(snapshot.needsAttentionCount) 件").font(.headline)
            }
            if snapshot.expiredCount > 0 {
                Text("已过期 \(snapshot.expiredCount)").font(.caption).foregroundStyle(.red)
            }
            if family != .systemSmall {
                ForEach(Array(snapshot.items.prefix(rowLimit).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(daysLabel(item.daysRemaining)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if snapshot.needsAttentionCount == 0 {
                Text("都很新鲜 🎉").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://expiring"))
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
    private func daysLabel(_ days: Int?) -> String {
        guard let days else { return "无到期" }
        if days < 0 { return "已过期" }
        if days == 0 { return "今天到期" }
        return "还剩 \(days) 天"
    }
}

// MARK: 今日膳食

struct MealPlanWidgetView: View {
    let snapshot: WidgetMealPlanSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife").foregroundStyle(.green)
                Text("今日膳食").font(.headline)
            }
            if snapshot.items.isEmpty {
                Text("今天还没排菜").font(.caption).foregroundStyle(.secondary)
            } else if family == .systemSmall {
                Text("\(snapshot.items.count) 顿待做").font(.subheadline)
            } else {
                ForEach(Array(snapshot.items.prefix(rowLimit).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Text(item.title).font(.subheadline).strikethrough(item.done).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://mealplan"))
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
}

// MARK: 购物(交互按钮在 Task 10 加入)

struct ShoppingWidgetView: View {
    let snapshot: WidgetShoppingSnapshot
    let family: WidgetFamily

    private static let shoppingURL = URL(string: "freshpantry://shopping")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题:medium/large 用 Link 承载深链,而非把 widgetURL 挂在整个容器上 ——
            // 容器级 widgetURL 会抢占/吞掉行内 Button(intent:) 的点击(iOS 17/18 已知
            // 行为),正是「勾选点了没反应」的根因。small 无交互按钮,整块仍走 widgetURL。
            if family == .systemSmall {
                header
            } else {
                Link(destination: Self.shoppingURL) { header }
            }
            if family == .systemSmall {
                if let first = snapshot.items.first { Text(first.name).font(.subheadline).lineLimit(1) }
            } else {
                ForEach(snapshot.items.prefix(rowLimit), id: \.id) { item in
                    ShoppingRowView(item: item)
                }
            }
            if snapshot.items.isEmpty {
                Text("清单是空的").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 仅 small(无交互按钮)整块深链;medium/large 置 nil(深链改由上面标题 Link 承载),
        // 避免容器 widgetURL 吞掉行内勾选按钮的点击。
        .widgetURL(family == .systemSmall ? Self.shoppingURL : nil)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "cart.fill").foregroundStyle(.blue)
            Text("购物 \(snapshot.uncheckedCount) 项待买").font(.headline)
        }
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 3 }
}

/// 单行购物项,带交互勾选(iOS 17+):**整行**(图标 + 名称 + 留白)都是勾选按钮。
/// 点击翻转 store + 重载时间线。整行可点 + `.contentShape(Rectangle())` 兜住命中区 ——
/// 避免「裸 SF Symbol 命中区收缩到 ~17pt + 容器 widgetURL 抢点」导致的「点了没反应」。
struct ShoppingRowView: View {
    let item: WidgetShoppingSnapshot.Item
    var body: some View {
        Button(intent: ToggleShoppingItemIntent(itemID: item.id)) {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .blue : .secondary)
                Text(item.name).font(.subheadline).strikethrough(item.isChecked).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: 减废

struct WasteWidgetView: View {
    let snapshot: WidgetWasteSnapshot
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                Text("减废成效").font(.headline)
            }
            if snapshot.isEmpty {
                Text("还没有记录").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(snapshot.useUpPercent)%").font(.system(size: family == .systemSmall ? 34 : 28, weight: .bold))
                Text("用掉率").font(.caption).foregroundStyle(.secondary)
                if family != .systemSmall {
                    Text("抢救临期 \(snapshot.rescuedCount) 件 · 浪费 \(snapshot.wastedCount) 件")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "freshpantry://waste"))
    }
}
