/// widget 内容类别。每个固定 widget 对应一类(见 FreshPantryWidget.swift)。
///
/// 历史:曾用 `AppEnum` + `SelectWidgetContentIntent`(`WidgetConfigurationIntent`)
/// 做单个可配置 widget,但真机 Release 包不认该配置 intent(长按无「编辑小组件」),
/// widget 卡在默认内容(临期),内容为空时看似空白。改为每类一个独立
/// StaticConfiguration widget 后,这里退化为普通枚举,仅用于内部按类别分发视图。
enum WidgetContentChoice {
    case expiring, mealPlan, shopping, waste
}
