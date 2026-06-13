import Foundation
import Testing
@testable import FreshPantry

/// UserDefaults 覆盖值 store:默认回落、覆盖读回、reset/resetAll、跨实例持久化、
/// 防御式 decode、suite 隔离。
@MainActor
struct FeatureFlagStoreTests {
    /// 每个测试一个隔离 suite,持久值不串。
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.featureflag.\(UUID().uuidString)")!
    }

    // MARK: 默认回落

    @Test func freshStoreReturnsCompiledDefault() {
        let store = FeatureFlagStore(defaults: suite())
        #expect(store.isEnabled(.demoFeature) == FeatureFlag.demoFeature.defaultValue)
        #expect(store.isOverridden(.demoFeature) == false)
    }

    // MARK: 覆盖 + 持久化

    @Test func setOverridesAndPersists() {
        let defaults = suite()
        let store = FeatureFlagStore(defaults: defaults)

        store.set(.demoFeature, true)
        #expect(store.isEnabled(.demoFeature) == true)
        #expect(store.isOverridden(.demoFeature) == true)

        // 同 suite 新实例读到持久覆盖。
        let reloaded = FeatureFlagStore(defaults: defaults)
        #expect(reloaded.isEnabled(.demoFeature) == true)
        #expect(reloaded.isOverridden(.demoFeature) == true)
    }

    // MARK: reset / resetAll

    @Test func resetClearsSingleOverride() {
        let defaults = suite()
        let store = FeatureFlagStore(defaults: defaults)
        store.set(.demoFeature, true)
        store.reset(.demoFeature)
        #expect(store.isOverridden(.demoFeature) == false)
        #expect(store.isEnabled(.demoFeature) == FeatureFlag.demoFeature.defaultValue)
        // 持久化:同 suite 新实例也看不到覆盖。
        #expect(FeatureFlagStore(defaults: defaults).isOverridden(.demoFeature) == false)
    }

    @Test func resetAllClearsEverything() {
        let defaults = suite()
        let store = FeatureFlagStore(defaults: defaults)
        store.set(.demoFeature, true)
        store.resetAll()
        #expect(store.isOverridden(.demoFeature) == false)
        // 持久化:同 suite 新实例也看不到覆盖。
        #expect(FeatureFlagStore(defaults: defaults).isOverridden(.demoFeature) == false)
    }

    // MARK: 防御式 decode

    @Test func decodeHandlesNilEmptyAndMalformed() {
        #expect(FeatureFlagStore.decode(nil).isEmpty)
        #expect(FeatureFlagStore.decode("").isEmpty)
        #expect(FeatureFlagStore.decode("not json").isEmpty)
        // 顶层数组而非对象 → 空。
        #expect(FeatureFlagStore.decode("[1,2,3]").isEmpty)
        // 合法对象:bool 值保留,非 bool 字符串值丢弃。
        let decoded = FeatureFlagStore.decode("{\"demoFeature\":true,\"x\":\"nope\"}")
        #expect(decoded["demoFeature"] == true)
        #expect(decoded["x"] == nil)
    }

    // MARK: suite 隔离

    @Test func suitesAreIsolated() {
        let a = FeatureFlagStore(defaults: suite())
        let b = FeatureFlagStore(defaults: suite())
        a.set(.demoFeature, true)
        #expect(b.isOverridden(.demoFeature) == false)
    }
}
