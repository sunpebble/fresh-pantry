import Foundation
import Testing
@testable import FreshPantry

/// The generic reconciliation sequence (ADR-0004) tested once through in-memory
/// closures — no `RemotePantryRepository`, no SwiftData. Because `EntitySync.make`
/// is generic over `SyncableEntity`, this exercises the apply path all seven
/// synced entities share.
struct EntitySyncTests {
    private actor Captured {
        private(set) var saved: [Ingredient] = []
        private(set) var signals = 0
        func record(_ rows: [Ingredient]) { saved = rows }
        func signal() { signals += 1 }
    }

    private func ingredient(_ id: String, name: String = "番茄", remoteVersion: Int) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份",
            imageUrl: "", freshnessPercent: 1, state: .fresh,
            remoteVersion: remoteVersion
        )
    }

    private func context(_ captured: Captured, current: Bool = true) -> SyncApplyContext {
        SyncApplyContext(
            householdId: "home",
            isCurrent: { current },
            loadPending: { [] },
            signalMerge: { await captured.signal() }
        )
    }

    private func plan(local: [Ingredient], captured: Captured) -> EntitySync {
        EntitySync.make(
            .inventoryItem,
            load: { _ in local },
            save: { _, rows in await captured.record(rows) },
            remoteLoad: { _, _ in [] },
            remoteUpsert: { _, _ in },
            watch: { _ in AsyncStream { $0.finish() } }
        )
    }

    @Test func applyFullMergesRemoteOverLocalOnlyThenSavesAndPulses() async {
        let captured = Captured()
        let local = [
            ingredient("local-1", name: "本地葱", remoteVersion: 0), // local-only → survives
            ingredient("synced-1", name: "已同步", remoteVersion: 4), // synced → dropped (remote is truth)
        ]
        let remoteRows = [DomainJSON.valueMap(ingredient("remote-1", name: "远端番茄", remoteVersion: 3))!]

        await plan(local: local, captured: captured).applyFull(remoteRows, context(captured))

        #expect(await captured.saved.map(\.id) == ["remote-1", "local-1"])
        #expect(await captured.signals == 1)
    }

    @Test func applyFullBailsWhenGenerationIsStale() async {
        let captured = Captured()
        let local = [ingredient("local-1", remoteVersion: 0)]

        await plan(local: local, captured: captured).applyFull([], context(captured, current: false))

        #expect(await captured.saved.isEmpty) // stale generation → no save
        #expect(await captured.signals == 0)
    }
}
