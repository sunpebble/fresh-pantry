import Foundation
import os

/// Owns the local⇄remote reconciliation for a household's shared content:
/// uploading local-only rows, subscribing to the four realtime streams, and
/// merging remote rows with still-pending local ones.
///
/// Ported from `lib/sync/household_content_sync_coordinator.dart`. The
/// generation + active-household guard (`isCurrent`) drops any in-flight result
/// whose household has since changed or whose owner was stopped, so a stale
/// apply can never clobber the current view (parity invariant #6).
///
/// `syncTo` is the single entry point (no-op when the household is unchanged);
/// `stop` cancels every subscription on teardown / sign-out. Every remote call
/// is `try?`/do-catch-logged — a remote or realtime failure must never crash
/// the app (invariant #9).
actor HouseholdContentSyncCoordinator {
    private let remote: RemotePantryRepository
    private let push: SyncCoordinator
    private let outbox: SyncOutboxRepository
    private let inventory: InventoryRepository
    private let shopping: ShoppingRepository
    private let customRecipe: CustomRecipeRepository
    private let mealPlan: MealPlanRepository
    private let foodLog: FoodLogRepository
    private let session: SyncSession

    private static let logger = Logger(subsystem: "com.kunish.freshPantry", category: "sync")

    /// The household currently reconciled. Empty = local-only (no sync running).
    private var activeHouseholdId = ""
    /// Bumped on every household switch / stop; the guard for in-flight applies.
    private var generation = 0
    /// The four realtime-subscription tasks; cancelled + cleared on switch/stop.
    private var subscriptionTasks: [Task<Void, Never>] = []
    /// The in-flight `startSync` task. The generation guard already drops a stale
    /// run's writes; cancelling it as well stops the stale run's remaining network
    /// calls instead of letting them run to completion.
    private var syncTask: Task<Void, Never>?

    init(
        remote: RemotePantryRepository,
        push: SyncCoordinator,
        outbox: SyncOutboxRepository,
        inventory: InventoryRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        foodLog: FoodLogRepository,
        session: SyncSession
    ) {
        self.remote = remote
        self.push = push
        self.outbox = outbox
        self.inventory = inventory
        self.shopping = shopping
        self.customRecipe = customRecipe
        self.mealPlan = mealPlan
        self.foodLog = foodLog
        self.session = session
    }

    /// Switches reconciliation to `householdId`. A no-op when unchanged; on a
    /// change it bumps the generation, cancels the old subscriptions, and (for a
    /// non-empty id) launches a fresh sync. An empty id stops sync (local-only).
    func syncTo(_ householdId: String) {
        if householdId == activeHouseholdId { return }
        activeHouseholdId = householdId
        generation += 1
        let gen = generation
        cancelSubscriptions()
        if householdId.isEmpty { return }
        syncTask = Task { await startSync(householdId, gen) }
    }

    /// Cancels all realtime subscriptions and stops reconciliation. Used on app
    /// teardown / sign-out; a later `syncTo` restarts from a clean state.
    func stop() {
        activeHouseholdId = ""
        generation += 1
        cancelSubscriptions()
    }

    // MARK: Sequence

    /// The load-bearing reconciliation sequence (each step re-checks `isCurrent`
    /// and bails): upload local-only → drain outbox → subscribe → bulk pull →
    /// apply. Never crashes — any thrown error is logged and swallowed.
    private func startSync(_ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        do {
            // One-shot legacy-id migration so historical fl_<ms> rows can backfill
            // into the uuid PK column. Idempotent — a no-op once everything is UUID.
            // Local-only SwiftData op: surface a failure rather than swallow it (a
            // swallowed failure would leave fl_ ids that re-upload as duplicate rows
            // because the codec skips a non-UUID id). Non-fatal: sync still proceeds.
            do {
                try await foodLog.migrateLegacyIds()
            } catch {
                Self.logger.error("FoodLog id migration failed: \(error.localizedDescription, privacy: .public)")
            }
            guard isCurrent(gen, householdId) else { return }

            let scope = LocalUploadScope(
                householdID: householdId,
                pendingOps: (try? await outbox.loadPending()) ?? []
            )

            try await uploadLocalOnly(householdId, gen, scope)
            guard isCurrent(gen, householdId) else { return }

            // Drain any queued outbox ops (incl. the rows just upserted as
            // local-only, plus pre-existing mutations).
            await push.pushPending()
            guard isCurrent(gen, householdId) else { return }

            subscribe(householdId, gen)
            guard isCurrent(gen, householdId) else { return }

            // Initial bulk pull — the realtime streams only yield future changes.
            let inventoryRows = try await remote.loadInventory(householdId)
            let shoppingRows = try await remote.loadShopping(householdId)
            let recipeRows = try await remote.loadCustomRecipes(householdId)
            let mealPlanRows = try await remote.loadMealPlanEntries(householdId)
            let foodLogRows = try await remote.loadFoodLogEntries(householdId)
            guard isCurrent(gen, householdId) else { return }

            await applyInventoryRows(inventoryRows, householdId, gen)
            await applyShoppingRows(shoppingRows, householdId, gen)
            await applyCustomRecipeRows(recipeRows, householdId, gen)
            await applyMealPlanRows(mealPlanRows, householdId, gen)
            await applyFoodLogRows(foodLogRows, householdId, gen)
        } catch is CancellationError {
            // A household switch / stop cancelled this run — not an error.
        } catch {
            Self.logger.error("while syncing household content: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Uploads the still-local-only rows of each entity to the remote (idempotent
    /// `upsert(ignoreDuplicates:)`, version forced to 1). Filtered by the same
    /// local-only predicate as the merge helper and gated by the upload scope so
    /// a row pending for another household never leaks here (invariant #7).
    private func uploadLocalOnly(_ householdId: String, _ gen: Int, _ scope: LocalUploadScope) async throws {
        guard isCurrent(gen, householdId) else { return }

        // After uploading a batch of local-only rows we mark them
        // `remoteVersion = 1` and persist, mirroring the Dart `_markLocalXUploaded`
        // + `replaceFromRemote`. Without it the rows stay `remoteVersion = 0` until
        // the bulk-pull merge corrects them, and an edit in that window would
        // enqueue a first-write upsert (ignoreDuplicates) that silently drops the
        // edit against the already-present remote row. `saveX` replaces the whole
        // scope, so we re-save the full local list with the uploaded ids bumped.

        // Inventory
        let localInventory = (try? await inventory.loadAllFor(householdId)) ?? []
        let uploadInventory = localInventory.filter {
            HouseholdMergePolicy.isLocalOnlyInventory($0) && scope.allows(.inventoryItem, $0.id)
        }
        if !uploadInventory.isEmpty {
            try await remote.upsertInventory(householdId, uploadInventory.compactMap { DomainJSON.valueMap($0) })
            guard isCurrent(gen, householdId) else { return }
            let uploaded = Set(uploadInventory.map(\.id))
            try? await inventory.saveItems(householdId, localInventory.map {
                uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
            })
        }

        // Shopping
        guard isCurrent(gen, householdId) else { return }
        let localShopping = (try? await shopping.loadAllFor(householdId)) ?? []
        let uploadShopping = localShopping.filter {
            HouseholdMergePolicy.isLocalOnlyShopping($0) && scope.allows(.shoppingItem, $0.id)
        }
        if !uploadShopping.isEmpty {
            try await remote.upsertShopping(householdId, uploadShopping.compactMap { DomainJSON.valueMap($0) })
            guard isCurrent(gen, householdId) else { return }
            let uploaded = Set(uploadShopping.map(\.id))
            try? await shopping.saveItems(householdId, localShopping.map {
                uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
            })
        }

        // Custom recipes
        guard isCurrent(gen, householdId) else { return }
        let localRecipes = (try? await customRecipe.loadAllFor(householdId)) ?? []
        let uploadRecipes = localRecipes.filter {
            HouseholdMergePolicy.isLocalOnlyRecipe($0) && scope.allows(.customRecipe, $0.id)
        }
        if !uploadRecipes.isEmpty {
            try await remote.upsertCustomRecipes(householdId, uploadRecipes.compactMap { DomainJSON.valueMap($0) })
            guard isCurrent(gen, householdId) else { return }
            let uploaded = Set(uploadRecipes.map(\.id))
            try? await customRecipe.saveRecipes(householdId, localRecipes.map {
                uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
            })
        }

        // Meal plan
        guard isCurrent(gen, householdId) else { return }
        let localMealPlan = (try? await mealPlan.loadAllFor(householdId)) ?? []
        let uploadMealPlan = localMealPlan.filter {
            HouseholdMergePolicy.isLocalOnlyMealPlan($0) && scope.allows(.mealPlanEntry, $0.id)
        }
        if !uploadMealPlan.isEmpty {
            try await remote.upsertMealPlanEntries(householdId, uploadMealPlan.compactMap { DomainJSON.valueMap($0) })
            guard isCurrent(gen, householdId) else { return }
            let uploaded = Set(uploadMealPlan.map(\.id))
            try? await mealPlan.saveEntries(householdId, localMealPlan.map {
                uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
            })
        }

        // Food log (append-only history → full backfill)
        guard isCurrent(gen, householdId) else { return }
        let localFoodLog = (try? await foodLog.loadAllFor(householdId)) ?? []
        let uploadFoodLog = localFoodLog.filter {
            HouseholdMergePolicy.isLocalOnlyFoodLog($0) && scope.allows(.foodLogEntry, $0.id)
        }
        if !uploadFoodLog.isEmpty {
            try await remote.upsertFoodLogEntries(householdId, uploadFoodLog.compactMap { DomainJSON.valueMap($0) })
            guard isCurrent(gen, householdId) else { return }
            let uploaded = Set(uploadFoodLog.map(\.id))
            try? await foodLog.saveEntries(householdId, localFoodLog.map {
                uploaded.contains($0.id) ? $0.copyWith(remoteVersion: 1) : $0
            })
        }
    }

    /// Starts the four realtime subscriptions. Each iterates the entity's
    /// non-throwing `AsyncStream` and applies every yielded snapshot under the
    /// generation guard. Stream errors are swallowed by construction (the stream
    /// is non-throwing — a transient channel drop never crashes; invariant #9).
    private func subscribe(_ householdId: String, _ gen: Int) {
        subscriptionTasks = [
            Task { [remote] in
                for await rows in await remote.watchInventory(householdId) {
                    await self.applyInventoryRows(rows, householdId, gen)
                }
            },
            Task { [remote] in
                for await rows in await remote.watchShopping(householdId) {
                    await self.applyShoppingRows(rows, householdId, gen)
                }
            },
            Task { [remote] in
                for await rows in await remote.watchCustomRecipes(householdId) {
                    await self.applyCustomRecipeRows(rows, householdId, gen)
                }
            },
            Task { [remote] in
                for await rows in await remote.watchMealPlanEntries(householdId) {
                    await self.applyMealPlanRows(rows, householdId, gen)
                }
            },
            Task { [remote] in
                for await rows in await remote.watchFoodLogEntries(householdId) {
                    await self.applyFoodLogRows(rows, householdId, gen)
                }
            },
        ]
    }

    // MARK: Apply (re-load scope + local INSIDE each — they evolve)

    private func applyInventoryRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        let decoded = rows
            .compactMap { DomainJSON.fromValueMap(Ingredient.self, from: $0) }
            .filter { !$0.id.isEmpty && !$0.name.trimmed.isEmpty }

        let scope = LocalUploadScope(
            householdID: householdId,
            pendingOps: (try? await outbox.loadPending()) ?? []
        )
        let local = (try? await inventory.loadAllFor(householdId)) ?? []
        let merged = HouseholdMergePolicy.mergeInventory(remote: decoded, local: local, scope: scope)

        guard isCurrent(gen, householdId) else { return }
        try? await inventory.saveItems(householdId, merged)
        await signalMerge()
    }

    private func applyShoppingRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        let decoded = rows
            .compactMap { DomainJSON.fromValueMap(ShoppingItem.self, from: $0) }
            .filter { !$0.id.isEmpty && !$0.name.trimmed.isEmpty }

        let scope = LocalUploadScope(
            householdID: householdId,
            pendingOps: (try? await outbox.loadPending()) ?? []
        )
        let local = (try? await shopping.loadAllFor(householdId)) ?? []
        let merged = HouseholdMergePolicy.mergeShopping(remote: decoded, local: local, scope: scope)

        guard isCurrent(gen, householdId) else { return }
        try? await shopping.saveItems(householdId, merged)
        await signalMerge()
    }

    private func applyCustomRecipeRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        let decoded = rows
            .compactMap { DomainJSON.fromValueMap(Recipe.self, from: $0) }
            .filter { !$0.id.isEmpty && !$0.name.trimmed.isEmpty }

        let scope = LocalUploadScope(
            householdID: householdId,
            pendingOps: (try? await outbox.loadPending()) ?? []
        )
        let local = (try? await customRecipe.loadAllFor(householdId)) ?? []
        let merged = HouseholdMergePolicy.mergeCustomRecipe(remote: decoded, local: local, scope: scope)

        guard isCurrent(gen, householdId) else { return }
        try? await customRecipe.saveRecipes(householdId, merged)
        await signalMerge()
    }

    private func applyMealPlanRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        // Tolerant per-row decode: `MealPlanEntry` decoding throws on a bad date,
        // and one malformed remote row must not abort the whole apply.
        let decoded = rows
            .compactMap { DomainJSON.fromValueMap(MealPlanEntry.self, from: $0) }
            .filter { !$0.id.isEmpty && !$0.recipeId.trimmed.isEmpty }

        let scope = LocalUploadScope(
            householdID: householdId,
            pendingOps: (try? await outbox.loadPending()) ?? []
        )
        let local = (try? await mealPlan.loadAllFor(householdId)) ?? []
        let merged = HouseholdMergePolicy.mergeMealPlan(remote: decoded, local: local, scope: scope)

        guard isCurrent(gen, householdId) else { return }
        try? await mealPlan.saveEntries(householdId, merged)
        await signalMerge()
    }

    private func applyFoodLogRows(_ rows: [[String: JSONValue]], _ householdId: String, _ gen: Int) async {
        guard isCurrent(gen, householdId) else { return }
        // Tolerant per-row decode: FoodLogEntry decoding throws on a bad loggedAt,
        // and one malformed remote row must not abort the whole apply.
        let decoded = rows
            .compactMap { DomainJSON.fromValueMap(FoodLogEntry.self, from: $0) }
            .filter { !$0.id.isEmpty && !$0.name.trimmed.isEmpty }

        let scope = LocalUploadScope(
            householdID: householdId,
            pendingOps: (try? await outbox.loadPending()) ?? []
        )
        let local = (try? await foodLog.loadAllFor(householdId)) ?? []
        let merged = HouseholdMergePolicy.mergeFoodLog(remote: decoded, local: local, scope: scope)

        guard isCurrent(gen, householdId) else { return }
        try? await foodLog.saveEntries(householdId, merged)
        await signalMerge()
    }

    /// Pulses the "remote data changed" revision so feature views reload. The
    /// session is `@MainActor`, so the bump hops to the main actor.
    private func signalMerge() async {
        await MainActor.run { session.bumpDataRevision() }
    }

    // MARK: Guards

    /// GENERATION GUARD: an in-flight async result is applied only while its
    /// household + generation still match the active one. A `syncTo`/`stop`
    /// between the read and the apply bumps the generation, dropping stale work.
    private func isCurrent(_ gen: Int, _ householdId: String) -> Bool {
        gen == generation && householdId == activeHouseholdId
    }

    private func cancelSubscriptions() {
        syncTask?.cancel()
        syncTask = nil
        for task in subscriptionTasks { task.cancel() }
        subscriptionTasks.removeAll()
    }
}
