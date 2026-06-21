import Foundation
import Testing
@testable import FreshPantry

/// Parity with the `_mergeRemoteXWithLocalOnly` + `_isLocalOnlyX` rules from
/// `lib/sync/household_content_sync_coordinator.dart`: remote rows are
/// authoritative; only un-uploaded local rows absent remotely AND allowed by the
/// upload scope survive alongside them. Tests target the generic
/// `merge`/`patch` (ADR-0004).
struct HouseholdMergePolicyTests {
    // MARK: Fixtures

    private let household = "house-1"

    private func localOnly(id: String, name: String = "本地") -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份",
            imageUrl: "", freshnessPercent: 1, state: .fresh,
            remoteVersion: 0
        )
    }

    private func remoteRow(id: String, name: String = "远端") -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: "1", unit: "份",
            imageUrl: "", freshnessPercent: 1, state: .fresh,
            remoteVersion: 3
        )
    }

    /// An empty scope (no pending ops) allows every non-empty id.
    private var openScope: LocalUploadScope {
        LocalUploadScope(householdID: household, pendingOps: [])
    }

    /// A pending op claims `entityID` for `otherHousehold`, so the row must NOT
    /// leak into `household`'s merge (invariant #7).
    private func scopeBlocking(entityID: String, forOtherHousehold otherHousehold: String) -> LocalUploadScope {
        let op = SyncOperation(
            id: "op-1",
            householdId: otherHousehold,
            entityType: .inventoryItem,
            entityId: entityID,
            operation: .create,
            patch: [:],
            clientId: "client-1",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return LocalUploadScope(householdID: household, pendingOps: [op])
    }

    // MARK: Tests

    @Test func remoteRowsAlwaysSurvive() {
        let merged = HouseholdMergePolicy.merge(
            remote: [remoteRow(id: "r1"), remoteRow(id: "r2")],
            local: [],
            scope: openScope,
            entityType: .inventoryItem
        )
        #expect(merged.map(\.id) == ["r1", "r2"])
    }

    @Test func localOnlyAbsentRemotelyAndAllowedIsAppended() {
        let merged = HouseholdMergePolicy.merge(
            remote: [remoteRow(id: "r1")],
            local: [localOnly(id: "l1")],
            scope: openScope,
            entityType: .inventoryItem
        )
        // Remote first, then the surviving local-only row.
        #expect(merged.map(\.id) == ["r1", "l1"])
    }

    @Test func localOnlyAlreadyPresentRemotelyIsNotDuplicated() {
        // The local row shares its id with a remote row → remote wins, no dup.
        let merged = HouseholdMergePolicy.merge(
            remote: [remoteRow(id: "shared", name: "远端版本")],
            local: [localOnly(id: "shared", name: "本地版本")],
            scope: openScope,
            entityType: .inventoryItem
        )
        #expect(merged.map(\.id) == ["shared"])
        #expect(merged.first?.name == "远端版本")
    }

    @Test func syncedLocalRowIsDropped() {
        // remoteVersion > 0 → not local-only → remote is the source of truth.
        let synced = localOnly(id: "s1").copyWith(remoteVersion: 5)
        let merged = HouseholdMergePolicy.merge(
            remote: [],
            local: [synced],
            scope: openScope,
            entityType: .inventoryItem
        )
        #expect(merged.isEmpty)
    }

    @Test func softDeletedLocalRowIsDropped() {
        // deletedAt != nil → not local-only → omitted from the merge.
        let deleted = localOnly(id: "d1").copyWith(deletedAt: Date(timeIntervalSince1970: 1))
        let merged = HouseholdMergePolicy.merge(
            remote: [],
            local: [deleted],
            scope: openScope,
            entityType: .inventoryItem
        )
        #expect(merged.isEmpty)
    }

    @Test func localOnlyBlockedByScopeForAnotherHouseholdIsDropped() {
        // A pending op claims "l1" for "house-2"; it must not leak into house-1.
        let scope = scopeBlocking(entityID: "l1", forOtherHousehold: "house-2")
        let merged = HouseholdMergePolicy.merge(
            remote: [],
            local: [localOnly(id: "l1")],
            scope: scope,
            entityType: .inventoryItem
        )
        #expect(merged.isEmpty)
    }

    @Test func blankNameLocalRowIsNotLocalOnly() {
        // Identity field blank → not local-only → dropped.
        let merged = HouseholdMergePolicy.merge(
            remote: [],
            local: [localOnly(id: "b1", name: "   ")],
            scope: openScope,
            entityType: .inventoryItem
        )
        #expect(merged.isEmpty)
    }

    // MARK: Other entity analogues (smoke-level parity)

    @Test func shoppingMergeAppendsLocalOnly() {
        let remote = ShoppingItem(id: "r1", name: "远端", detail: "", category: "其他", remoteVersion: 2)
        let local = ShoppingItem(id: "l1", name: "本地", detail: "", category: "其他", remoteVersion: 0)
        let merged = HouseholdMergePolicy.merge(
            remote: [remote], local: [local],
            scope: LocalUploadScope(householdID: household, pendingOps: []),
            entityType: .shoppingItem
        )
        #expect(merged.map(\.id) == ["r1", "l1"])
    }

    @Test func recipeMergeDropsSyncedLocal() {
        let synced = Recipe(
            id: "l1", name: "本地", category: "", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: [], steps: [], remoteVersion: 4
        )
        let merged = HouseholdMergePolicy.merge(
            remote: [], local: [synced],
            scope: LocalUploadScope(householdID: household, pendingOps: []),
            entityType: .customRecipe
        )
        #expect(merged.isEmpty)
    }

    @Test func mealPlanMergeRequiresRecipeId() {
        // recipeId blank → not local-only → dropped.
        let entry = MealPlanEntry(
            id: "m1", date: Date(timeIntervalSince1970: 0),
            recipeId: "", recipeName: "无食谱", remoteVersion: 0
        )
        let merged = HouseholdMergePolicy.merge(
            remote: [], local: [entry],
            scope: LocalUploadScope(householdID: household, pendingOps: []),
            entityType: .mealPlanEntry
        )
        #expect(merged.isEmpty)
    }

    // MARK: Incremental patch

    @Test func patchInventoryUpsertsAndDeletes() {
        let local = [
            remoteRow(id: "r1", name: "旧番茄"),
            localOnly(id: "l1", name: "本地葱"),
        ]
        let delta = [
            remoteRow(id: "r1", name: "新番茄"),
            remoteRow(id: "r2", name: "远端米"),
            remoteRow(id: "r1", name: "删番茄").copyWith(deletedAt: Date(timeIntervalSince1970: 1)),
        ]
        let merged = HouseholdMergePolicy.patch(remoteDelta: delta, local: local)
        #expect(merged.map(\.id) == ["l1", "r2"])
        #expect(merged.first(where: { $0.id == "r2" })?.name == "远端米")
    }
}
