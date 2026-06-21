import Foundation
import Testing
@testable import FreshPantry

/// FoodLog merge is append-only: the union of remote rows and local-only rows
/// (never-synced, not claimed by another household's pending op).
struct FoodLogMergeTests {
    private func entry(_ id: String, remoteVersion: Int) -> FoodLogEntry {
        FoodLogEntry(id: id, name: "x", outcome: .consumed,
                     loggedAt: Date(timeIntervalSince1970: 1_700_000_000),
                     remoteVersion: remoteVersion)
    }

    @Test func mergeIsUnionOfRemoteAndLocalOnly() {
        let remote = [entry("11111111-1111-4111-8111-111111111111", remoteVersion: 3)]
        let local = [
            entry("11111111-1111-4111-8111-111111111111", remoteVersion: 3), // already remote → not re-added
            entry("22222222-2222-4222-8222-222222222222", remoteVersion: 0), // local-only → kept
        ]
        let scope = LocalUploadScope(householdID: "home", pendingOps: [])
        let merged = HouseholdMergePolicy.merge(remote: remote, local: local, scope: scope, entityType: .foodLogEntry)
        #expect(merged.map(\.id) == [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
        ])
    }

    @Test func localOnlyGuardRejectsBlankNameAndSynced() {
        #expect(entry("33333333-3333-4333-8333-333333333333", remoteVersion: 0).isLocalOnly)
        #expect(!entry("44444444-4444-4444-8444-444444444444", remoteVersion: 5).isLocalOnly) // synced
        let blank = FoodLogEntry(id: "55555555-5555-4555-8555-555555555555", name: "  ", outcome: .consumed,
                                 loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!blank.isLocalOnly) // blank name rejected
    }
}
