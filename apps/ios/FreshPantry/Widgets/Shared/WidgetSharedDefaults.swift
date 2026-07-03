import Foundation

/// 主 app 与小组件扩展共用的 App Group 标识符。须与两个 target 的
/// `.entitlements` 里的 `application-groups` 一致;`WidgetSnapshotStore` /
/// `WidgetPendingToggleStore` / `ModelContainerFactory` 用它解析共享容器 URL。
public enum WidgetSharedDefaults {
    public static let appGroupID = "group.com.sunpebble.freshpantry"
}
