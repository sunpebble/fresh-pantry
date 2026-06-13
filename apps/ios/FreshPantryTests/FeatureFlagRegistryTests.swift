import Testing
@testable import FreshPantry

/// 注册表 sanity:每个 flag 的展示元数据非空,且至少存在示例 flag。
struct FeatureFlagRegistryTests {
    @Test func everyFlagHasNonEmptyMetadata() {
        for flag in FeatureFlag.allCases {
            #expect(!flag.title.isEmpty)
            #expect(!flag.summary.isEmpty)
        }
    }

    @Test func demoFeatureExistsAndDefaultsOff() {
        #expect(FeatureFlag.allCases.contains(.demoFeature))
        #expect(FeatureFlag.demoFeature.defaultValue == false)
    }
}
