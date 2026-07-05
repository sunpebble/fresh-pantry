import AppIntents

/// widget 内容类别。固定 widget(临期/今日膳食/购物/减废各一个)按类分发视图;
/// 另有一个可配置 widget 用 `SelectWidgetContentIntent` 让用户切换内容。
///
/// ⚠️ 与 `ToggleShoppingItemIntent` 同理:配置 intent `SelectWidgetContentIntent` 须经
/// dual-target membership 编进 app + widget 两个 target(见 project.yml),**不要收进
/// framework** —— 否则 release 下 linkd 不注册进运行时索引(FB #425),真机表现为可配置
/// widget 占位 + 长按无「编辑小组件」。
public enum WidgetContentChoice: String, AppEnum {
    case expiring, mealPlan, shopping, waste

    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "widget.content.type" }
    public static var caseDisplayRepresentations: [WidgetContentChoice: DisplayRepresentation] {
        [
            .expiring: "widgetContent.expiring",
            .mealPlan: "widgetContent.mealPlan",
            .shopping: "widgetContent.shopping",
            .waste: "widgetContent.waste",
        ]
    }
}

/// widget 配置 intent:选择展示哪类内容(默认临期)。
public struct SelectWidgetContentIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "widget.select.title" }
    public static var description: IntentDescription { "widget.select.description" }

    @Parameter(title: "widget.select.parameter.content", default: .expiring)
    public var content: WidgetContentChoice

    public init() {}
}
