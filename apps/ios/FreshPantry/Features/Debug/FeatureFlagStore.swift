import Foundation

/// UserDefaults backing 的 feature-flag 覆盖值 —— 沿用 `AppearanceStore` /
/// `FavoritesStore` 的 KV 模板:`@Observable @MainActor`、可注入 suite、防御式
/// decode。只存**每-flag 覆盖**(`[String: Bool]` JSON 对象,key
/// `feature_flag_overrides_v1`,键为 `FeatureFlag.rawValue`)。无覆盖回落到
/// `FeatureFlag.defaultValue`,所以改某 flag 的编译期默认值会立刻影响所有未显式
/// 覆盖该 flag 的设备。设备本地:排除备份 / 家庭同步。
@Observable
@MainActor
final class FeatureFlagStore {
    static let storageKey = "feature_flag_overrides_v1"

    private let defaults: UserDefaults

    /// 按 `FeatureFlag.rawValue` 键存的实时覆盖表;缺键 → 回落编译期默认。
    /// 改动同步持久化。
    private(set) var overrides: [String: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = Self.decode(defaults.string(forKey: Self.storageKey))
    }

    // MARK: 查询

    /// 有效值:有设备覆盖取覆盖,否则取编译期默认。
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        overrides[flag.rawValue] ?? flag.defaultValue
    }

    /// 是否存在设备覆盖(驱动「已覆盖 / 默认」标签)。
    func isOverridden(_ flag: FeatureFlag) -> Bool {
        overrides[flag.rawValue] != nil
    }

    // MARK: 变更

    /// 设置(覆盖)某 flag 并持久化。
    func set(_ flag: FeatureFlag, _ on: Bool) {
        overrides[flag.rawValue] = on
        persist()
    }

    /// 清单个 flag 的覆盖 → 回落编译期默认。
    func reset(_ flag: FeatureFlag) {
        overrides[flag.rawValue] = nil
        persist()
    }

    /// 清空所有覆盖 → 全部回落编译期默认。
    func resetAll() {
        overrides = [:]
        persist()
    }

    // MARK: 持久化(JSON 对象 KV 编解码,镜像 FavoritesStore)

    /// 把覆盖表编码为 JSON 对象写入。编码失败静默不写(本会话内存值仍生效)。
    private func persist() {
        guard
            let data = try? JSONSerialization.data(withJSONObject: overrides),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        defaults.set(json, forKey: Self.storageKey)
    }

    /// 防御式 decode:nil/空/非对象/损坏 → 空覆盖表;否则取 `String: Bool` 条目
    /// (非 bool 值丢弃)。
    static func decode(_ raw: String?) -> [String: Bool] {
        guard
            let raw, !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object.compactMapValues { $0 as? Bool }
    }
}
