import Foundation
import SwiftUI
import Testing
@testable import FreshPantry

/// Tests for the UserDefaults-backed appearance KV store: default value,
/// mutation + persistence round-trip via an injected suite, defensive decode,
/// and the `preferredColorScheme` mapping.
@MainActor
struct AppearanceStoreTests {
    /// A fresh isolated suite per test so persisted values never leak between runs.
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
    }

    // MARK: Defaults

    @Test func freshStoreFollowsSystem() {
        let store = AppearanceStore(defaults: suite())
        #expect(store.mode == .system)
    }

    // MARK: Mutation + persistence

    @Test func setMutatesAndPersists() {
        let defaults = suite()
        let store = AppearanceStore(defaults: defaults)

        store.set(.dark)
        #expect(store.mode == .dark)
        #expect(defaults.string(forKey: AppearanceStore.storageKey) == "dark")

        // A new store over the same suite reads the persisted value.
        let reloaded = AppearanceStore(defaults: defaults)
        #expect(reloaded.mode == .dark)

        store.set(.light)
        #expect(AppearanceStore(defaults: defaults).mode == .light)
    }

    // MARK: Defensive decode

    @Test func decodeHandlesNilEmptyAndUnknown() {
        #expect(AppearanceStore.decode(nil) == .system)
        #expect(AppearanceStore.decode("") == .system)
        #expect(AppearanceStore.decode("amoled") == .system)
        #expect(AppearanceStore.decode("dark") == .dark)
        #expect(AppearanceStore.decode("light") == .light)
        #expect(AppearanceStore.decode("system") == .system)
    }

    // MARK: ColorScheme mapping

    @Test func colorSchemeMapping() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
