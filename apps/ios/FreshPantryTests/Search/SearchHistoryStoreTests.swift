import Foundation
import Testing
@testable import FreshPantry

/// Behavior tests for `SearchHistoryStore` — the ordered, capped, dedup-to-front
/// recent-search list (ports the Flutter `SearchHistoryNotifier`).
@MainActor
struct SearchHistoryStoreTests {
    private func makeStore() -> SearchHistoryStore {
        SearchHistoryStore(defaults: UserDefaults(suiteName: "test.search.\(UUID().uuidString)")!)
    }

    @Test func recordPutsMostRecentFirstAndDedups() {
        let store = makeStore()
        store.record("番茄")
        store.record("鸡蛋")
        store.record("番茄") // re-search moves it to front, no dup
        #expect(store.entries == ["番茄", "鸡蛋"])
    }

    @Test func recordIsCaseInsensitiveDedup() {
        let store = makeStore()
        store.record("Milk")
        store.record("milk")
        #expect(store.entries == ["milk"]) // latest casing wins, single entry
    }

    @Test func recordCapsAtTen() {
        let store = makeStore()
        for i in 1...12 { store.record("q\(i)") }
        #expect(store.entries.count == 10)
        #expect(store.entries.first == "q12") // newest first
        #expect(!store.entries.contains("q1")) // oldest dropped
        #expect(!store.entries.contains("q2"))
    }

    @Test func blankRecordIsNoOp() {
        let store = makeStore()
        store.record("   ")
        #expect(store.entries.isEmpty)
    }

    @Test func removeAndClear() {
        let store = makeStore()
        store.record("a"); store.record("b"); store.record("c")
        store.remove("b")
        #expect(store.entries == ["c", "a"])
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test func persistsAcrossInstancesPreservingOrder() {
        let suite = "test.search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = SearchHistoryStore(defaults: defaults)
        first.record("番茄")
        first.record("鸡蛋")
        // A fresh instance reads the persisted recency order (NOT sorted).
        let reloaded = SearchHistoryStore(defaults: defaults)
        #expect(reloaded.entries == ["鸡蛋", "番茄"])
    }
}
