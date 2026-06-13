/// 所有 feature flag 的注册表 —— 「存在哪些 flag」的单一真相。每个 case 携带
/// 调试菜单展示元数据与编译期默认值。新增 flag = 加一个 case + 三个属性分支。
/// `rawValue` 同时用作 UserDefaults 覆盖键,故重命名 case 会丢弃已存覆盖(可接受:
/// 覆盖是设备本地调试状态,非用户数据)。
///
/// 纯本地:取值 = 编译期 `defaultValue` + `FeatureFlagStore` 的可选设备覆盖,
/// 无后端/无 schema/无同步(见 `2026-06-13-feature-flags-design.md`)。
enum FeatureFlag: String, CaseIterable, Sendable {
    /// 无害示例 flag,证明端到端链路(调试切换 → Settings 行即时出现)。
    /// 默认关闭,可安全随包发布。
    case demoFeature

    /// 调试菜单行标题。
    var title: String {
        switch self {
        case .demoFeature: "示例功能"
        }
    }

    /// 调试菜单一句话说明。
    var summary: String {
        switch self {
        case .demoFeature: "演示用开关:开启后设置页出现一条演示行"
        }
    }

    /// 无设备覆盖时的编译期默认值。WIP flag 一律发 `false`。
    var defaultValue: Bool {
        switch self {
        case .demoFeature: false
        }
    }
}
