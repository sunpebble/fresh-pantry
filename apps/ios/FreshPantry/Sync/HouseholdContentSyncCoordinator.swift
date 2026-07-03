import Foundation
import os

/// Owns the local⇄remote reconciliation for a household's shared content:
/// uploading local-only rows, subscribing to the seven realtime streams, and
/// merging remote rows with still-pending local ones.
///
/// Ported from `lib/sync/household_content_sync_coordinator.dart`, then deepened
/// (ADR-0004): the seven entities' reconciliation, once 21 hand-rolled blocks,
/// now lives in one `[EntitySync]` (`entitySyncs`) the sequence loops over. The
/// per-entity decode→merge→save→signal logic is written once in `EntitySync.make`.
///
/// The generation + active-household guard (`isCurrent`) drops any in-flight
/// result whose household has since changed or whose owner was stopped, so a stale
/// apply can never clobber the current view (parity invariant #6). It is reached
/// from the generic sequence through `SyncApplyContext` (built per run).
///
/// `syncTo` is the single entry point (no-op when the household is unchanged);
/// `stop` cancels every subscription on teardown / sign-out. Every remote call
/// is `try?`/do-catch-logged — a remote or realtime failure must never crash
/// the app (invariant #9).
actor HouseholdContentSyncCoordinator {
    private let remote: RemotePantryRepository
    private let push: SyncCoordinator
    private let outbox: SyncOutboxRepository
    private let foodLog: FoodLogRepository
    private let session: SyncSession
    private let diagnostics: Diagnostics

    /// The seven entities' reconciliation, in apply order (inventory → shopping →
    /// recipe → meal plan → food log → favorite → dietary). The single registry:
    /// adding a synced entity is one `EntitySync.make` line here (ADR-0004).
    private let entitySyncs: [EntitySync]

    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "sync")

    /// The household currently reconciled. Empty = local-only (no sync running).
    private var activeHouseholdId = ""
    /// Bumped on every household switch / stop; the guard for in-flight applies.
    private var generation = 0
    /// The seven realtime-subscription tasks; cancelled + cleared on switch/stop.
    private var subscriptionTasks: [Task<Void, Never>] = []
    /// The in-flight `startSync` task. The generation guard already drops a stale
    /// run's writes; cancelling it as well stops the stale run's remaining network
    /// calls instead of letting them run to completion.
    private var syncTask: Task<Void, Never>?
    /// Set when a `startSync` run threw before completing (e.g. an offline launch
    /// failing the bulk pull): inbound sync is absent until a re-run, so the app
    /// root retries via `retryIfNeeded` on reconnect / foreground. Cleared on any
    /// fresh `syncTo` / `stop` / consumed retry.
    private var needsRetry = false

    init(
        remote: RemotePantryRepository,
        push: SyncCoordinator,
        outbox: SyncOutboxRepository,
        inventory: InventoryRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        foodLog: FoodLogRepository,
        favoriteRecipe: FavoriteRecipeRepository,
        dietaryPreference: DietaryPreferenceRepository,
        session: SyncSession,
        diagnostics: Diagnostics = NoopDiagnostics()
    ) {
        self.remote = remote
        self.push = push
        self.outbox = outbox
        self.foodLog = foodLog
        self.session = session
        self.diagnostics = diagnostics

        // The single entity registry. Each `make` binds one entity's local repo +
        // remote I/O; the generic sequence (decode→merge→save→signal) lives in
        // `EntitySync.make`. The closures capture only the (Sendable) repos +
        // remote, never `self`, so `entitySyncs` stays Sendable. Order is the
        // load-bearing apply order (parity invariant #6 cursor-advance relies on it).
        self.entitySyncs = [
            EntitySync.make(
                .inventoryItem,
                load: { try await inventory.loadAllFor($0) },
                save: { try await inventory.saveItems($0, $1) },
                remoteLoad: { try await remote.loadInventory($0, since: $1) },
                remoteUpsert: { try await remote.upsertInventory($0, $1) },
                watch: { await remote.watchInventory($0) }
            ),
            EntitySync.make(
                .shoppingItem,
                load: { try await shopping.loadAllFor($0) },
                save: { try await shopping.saveItems($0, $1) },
                remoteLoad: { try await remote.loadShopping($0, since: $1) },
                remoteUpsert: { try await remote.upsertShopping($0, $1) },
                watch: { await remote.watchShopping($0) }
            ),
            EntitySync.make(
                .customRecipe,
                load: { try await customRecipe.loadAllFor($0) },
                save: { try await customRecipe.saveRecipes($0, $1) },
                remoteLoad: { try await remote.loadCustomRecipes($0, since: $1) },
                remoteUpsert: { try await remote.upsertCustomRecipes($0, $1) },
                watch: { await remote.watchCustomRecipes($0) }
            ),
            EntitySync.make(
                .mealPlanEntry,
                load: { try await mealPlan.loadAllFor($0) },
                save: { try await mealPlan.saveEntries($0, $1) },
                remoteLoad: { try await remote.loadMealPlanEntries($0, since: $1) },
                remoteUpsert: { try await remote.upsertMealPlanEntries($0, $1) },
                watch: { await remote.watchMealPlanEntries($0) }
            ),
            EntitySync.make(
                .foodLogEntry,
                load: { try await foodLog.loadAllFor($0) },
                save: { try await foodLog.saveEntries($0, $1) },
                remoteLoad: { try await remote.loadFoodLogEntries($0, since: $1) },
                remoteUpsert: { try await remote.upsertFoodLogEntries($0, $1) },
                watch: { await remote.watchFoodLogEntries($0) }
            ),
            EntitySync.make(
                .favoriteRecipe,
                load: { try await favoriteRecipe.loadAllFor($0) },
                save: { try await favoriteRecipe.saveEntries($0, $1) },
                remoteLoad: { try await remote.loadFavoriteRecipes($0, since: $1) },
                remoteUpsert: { try await remote.upsertFavoriteRecipes($0, $1) },
                watch: { await remote.watchFavoriteRecipes($0) }
            ),
            EntitySync.make(
                .dietaryPreference,
                load: { try await dietaryPreference.loadAllFor($0) },
                save: { try await dietaryPreference.saveEntries($0, $1) },
                remoteLoad: { try await remote.loadDietaryPreferences($0, since: $1) },
                remoteUpsert: { try await remote.upsertDietaryPreferences($0, $1) },
                watch: { await remote.watchDietaryPreferences($0) }
            ),
        ]
    }

    /// Switches reconciliation to `householdId`. A no-op when unchanged; on a
    /// change it bumps the generation, cancels the old subscriptions, and (for a
    /// non-empty id) launches a fresh sync. An empty id stops sync (local-only).
    func syncTo(_ householdId: String) {
        if householdId == activeHouseholdId { return }
        activeHouseholdId = householdId
        generation += 1
        let gen = generation
        needsRetry = false
        cancelSubscriptions()
        if householdId.isEmpty { return }
        syncTask = Task { await startSync(householdId, gen, forceFullPull: false) }
    }

    /// Cancels all realtime subscriptions and stops reconciliation. Used on app
    /// teardown / sign-out; a later `syncTo` restarts from a clean state.
    func stop() {
        activeHouseholdId = ""
        generation += 1
        needsRetry = false
        cancelSubscriptions()
    }

    /// Re-runs the full sync sequence for the active household IF the last run
    /// failed (an offline launch's bulk pull, a transient remote error) —
    /// otherwise a no-op, so it's safe to call on every reconnect / foreground.
    /// Bumping the generation + cancelling the old subscriptions first means a
    /// retry can never double-subscribe on top of a partially-started run.
    func retryIfNeeded() {
        guard Self.shouldRetry(needsRetry: needsRetry, activeHouseholdId: activeHouseholdId) else { return }
        needsRetry = false
        generation += 1
        let gen = generation
        let householdId = activeHouseholdId
        cancelSubscriptions()
        syncTask = Task { await startSync(householdId, gen, forceFullPull: true) }
    }

    /// Lightweight inbound refresh: incremental pull + patch when a cursor
    /// exists. No-op when local-only, mid-sync, or before the first full pull.
    func refreshDelta() async {
        let householdId = activeHouseholdId
        guard !householdId.isEmpty else { return }
        let cursor = await MainActor.run { session.syncCursor(for: householdId) }
        guard let since = cursor else { return }
        let gen = generation
        guard isCurrent(gen, householdId) else { return }
        do {
            let loaded = try await loadAllRemotes(householdId, since: since)
            guard isCurrent(gen, householdId) else { return }

            let ctx = makeContext(householdId, gen)
            for (sync, rows) in zip(entitySyncs, loaded) {
                await sync.applyPatch(rows, ctx)
            }

            await advanceCursor(from: since, loaded: loaded, householdId: householdId)
        } catch is CancellationError {
        } catch {
            Self.logger.error("while refreshing household delta: \(error.localizedDescription, privacy: .public)")
            diagnostics.failure("sync.pull", error: error, ["phase": "delta"])
        }
    }

    /// The retry gate, extracted pure for unit tests: only a marked-failed run
    /// with a still-active (non-local-only) household warrants a re-run.
    static func shouldRetry(needsRetry: Bool, activeHouseholdId: String) -> Bool {
        needsRetry && !activeHouseholdId.isEmpty
    }

    // MARK: Sequence

    /// The load-bearing reconciliation sequence (each step re-checks `isCurrent`
    /// and bails): upload local-only → drain outbox → subscribe → bulk pull →
    /// apply. Never crashes — any thrown error is logged and swallowed.
    private func startSync(_ householdId: String, _ gen: Int, forceFullPull: Bool) async {
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
                diagnostics.failure("sync.migrate", error: error, [:])
            }
            guard isCurrent(gen, householdId) else { return }

            let ctx = makeContext(householdId, gen)

            // Upload the still-local-only rows of every entity (idempotent
            // `upsert(ignoreDuplicates:)`, version forced to 1), then mark them
            // synced. One shared scope built here (parity invariant #7) so a row
            // pending for another household never leaks.
            let scope = LocalUploadScope(
                householdID: householdId,
                pendingOps: (try? await outbox.loadPending()) ?? []
            )
            for sync in entitySyncs {
                try await sync.uploadLocalOnly(scope, ctx)
                guard isCurrent(gen, householdId) else { return }
            }

            // Drain any queued outbox ops (incl. the rows just upserted as
            // local-only, plus pre-existing mutations).
            await push.pushPending()
            guard isCurrent(gen, householdId) else { return }

            subscribe(householdId, gen)
            guard isCurrent(gen, householdId) else { return }

            // Bulk pull — realtime only yields future changes. Reuse the stored
            // cursor for an incremental patch when the last run succeeded.
            let cursor = await MainActor.run { session.syncCursor(for: householdId) }
            let since = forceFullPull ? nil : cursor
            let loaded = try await loadAllRemotes(householdId, since: since)
            guard isCurrent(gen, householdId) else { return }

            if since == nil {
                for (sync, rows) in zip(entitySyncs, loaded) {
                    await sync.applyFull(rows, ctx)
                }
            } else {
                for (sync, rows) in zip(entitySyncs, loaded) {
                    await sync.applyPatch(rows, ctx)
                }
            }

            await advanceCursor(from: cursor, loaded: loaded, householdId: householdId)
            diagnostics.breadcrumb("sync.pull", ["outcome": "ok", "mode": since == nil ? "full" : "delta"])
        } catch is CancellationError {
            // A household switch / stop cancelled this run — not an error.
        } catch {
            Self.logger.error("while syncing household content: \(error.localizedDescription, privacy: .public)")
            diagnostics.failure("sync.pull", error: error, ["phase": "startSync"])
            // Mark the run failed so the next reconnect / foreground re-runs the
            // whole sequence (without this, an offline launch left inbound sync
            // absent for the rest of the session — `syncTo` no-ops on the same
            // id). Only while still current: a superseded run must not re-arm.
            if isCurrent(gen, householdId) {
                needsRetry = true
                await MainActor.run { session.setSyncCursor(nil, for: householdId) }
            }
        }
    }

    /// Bulk pull of every entity's remote rows, in `entitySyncs` order (so the
    /// `zip` apply and the cursor-advance line up). A nil `since` is a full pull.
    private func loadAllRemotes(_ householdId: String, since: Date?) async throws -> [[[String: JSONValue]]] {
        var loaded: [[[String: JSONValue]]] = []
        loaded.reserveCapacity(entitySyncs.count)
        for sync in entitySyncs {
            loaded.append(try await sync.remoteLoad(householdId, since))
        }
        return loaded
    }

    /// Advances the stored cursor to the newest `updated_at` across every entity's
    /// pulled rows (nil when nothing advanced). Mirrors the old per-entity
    /// `SyncCursor.advance(…)` array.
    private func advanceCursor(from cursor: Date?, loaded: [[[String: JSONValue]]], householdId: String) async {
        let advanced = loaded.compactMap { SyncCursor.advance(cursor, with: $0) }.max()
        if let advanced {
            await MainActor.run { session.setSyncCursor(advanced, for: householdId) }
        }
    }

    /// Starts the seven realtime subscriptions. Each iterates the entity's
    /// non-throwing `AsyncStream` and applies every yielded snapshot under the
    /// generation guard (carried by `ctx`). Stream errors are swallowed by
    /// construction (the stream is non-throwing — a transient channel drop never
    /// crashes; invariant #9).
    private func subscribe(_ householdId: String, _ gen: Int) {
        let ctx = makeContext(householdId, gen)
        subscriptionTasks = entitySyncs.map { sync in
            Task {
                for await rows in await sync.watch(householdId) {
                    await sync.applyFull(rows, ctx)
                }
            }
        }
    }

    /// Builds the per-run externalities the generic sequence needs from the live
    /// actor. `[weak self]` so a stale subscription task can't keep the
    /// coordinator alive; a deallocated coordinator reports "not current" and the
    /// apply bails.
    private func makeContext(_ householdId: String, _ gen: Int) -> SyncApplyContext {
        SyncApplyContext(
            householdId: householdId,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return await self.isCurrent(gen, householdId)
            },
            loadPending: { [weak self] in
                guard let self else { return [] }
                return (try? await self.outbox.loadPending()) ?? []
            },
            signalMerge: { [weak self] in await self?.signalMerge() }
        )
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
