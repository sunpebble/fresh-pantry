import Foundation

/// CRUD owner for the user's custom (hand-authored) recipes — the data half of
/// the authoring feature (the form is the UI). The reusable `@Observable
/// @MainActor` store template, mirroring `InventoryStore` / `ShoppingStore`:
/// every mutation loads the current household scope, mutates it, persists the
/// WHOLE scope through `CustomRecipeRepository.saveRecipes`, enqueues the sync
/// op, then reloads. A failed save returns `false` + sets `errorMessage` — never
/// a half-applied write.
///
/// Sync wiring (the last entity onto the outbox write-path): create →
/// `baseVersion = nil`; update → `baseVersion = remoteVersion`; delete → the
/// removed row as the patch so the gateway derives `deleted_at`,
/// `baseVersion = remoteVersion`. The enqueue is a no-op without a household
/// (`SyncWriter` handles that), so the store works purely locally too.
@Observable
@MainActor
final class CustomRecipeStore {
    private let repository: CustomRecipeRepository
    private let householdID: String
    /// Optional outbox seam — nil keeps tests/previews local-only.
    private let syncWriter: SyncWriter?

    /// The household's custom recipes, in repo order.
    private(set) var recipes: [Recipe] = []
    private(set) var isSaving = false
    var errorMessage: String?

    init(
        repository: CustomRecipeRepository,
        householdID: String,
        syncWriter: SyncWriter? = nil
    ) {
        self.repository = repository
        self.householdID = householdID
        self.syncWriter = syncWriter
    }

    // MARK: Loading

    /// Loads the household scope off the repo actor. A load error surfaces an
    /// empty scope rather than crashing (nothing to show).
    func load() async {
        recipes = (try? await repository.loadAllFor(householdID)) ?? []
    }

    // MARK: Mutations

    /// Appends a new recipe to the household scope OPTIMISTICALLY (the detail /
    /// list reflects it this tick), persists, enqueues a `.create` (baseVersion
    /// nil). Returns whether the write landed (false rolls back).
    @discardableResult
    func add(_ recipe: Recipe) async -> Bool {
        await mutate(apply: { recipes in recipes.append(recipe); return true }) {
            await self.syncWriter?.enqueue(recipe, type: .customRecipe, operation: .create, baseVersion: nil)
        }
    }

    /// Replaces the recipe with the same id OPTIMISTICALLY, persists, enqueues an
    /// `.update` (baseVersion = the recipe's remoteVersion). Returns whether the
    /// write landed (false when no row matched, or rolls back on a persist error).
    @discardableResult
    func update(_ recipe: Recipe) async -> Bool {
        await mutate(
            apply: { recipes in
                guard recipes.contains(where: { $0.id == recipe.id }) else { return false }
                recipes = recipes.map { $0.id == recipe.id ? recipe : $0 }
                return true
            },
            enqueue: {
                await self.syncWriter?.enqueue(recipe, type: .customRecipe, operation: .update, baseVersion: recipe.remoteVersion)
            }
        )
    }

    /// Drops the recipe with `id` from the household scope OPTIMISTICALLY,
    /// persists, enqueues a `.delete` (patch = the removed row so the gateway
    /// derives `deleted_at`, baseVersion = the removed row's remoteVersion).
    /// Returns whether the write landed (false when no row matched / rolled back).
    @discardableResult
    func remove(_ id: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let snapshot = recipes
        recipes = recipes.filter { $0.id != id } // optimistic reflect

        // Atomic load→remove→save, threading the removed row (for the outbox +
        // cover cleanup) out of the ONE actor hop — no window for a concurrent
        // sync mutate to be reverted. `nil` removed = no matching row.
        let outcome: (saved: [Recipe], removed: Recipe?)
        do {
            outcome = try await repository.mutateRecipesReturning(householdID) { current -> ([Recipe]?, (saved: [Recipe], removed: Recipe?)) in
                guard let match = current.first(where: { $0.id == id }) else { return (nil, (current, nil)) }
                let next = current.filter { $0.id != id }
                return (next, (next, match))
            }
        } catch {
            recipes = snapshot // rollback
            errorMessage = String(localized: "recipe.form.saveFailedRetry")
            return false
        }
        guard let removed = outcome.removed else {
            recipes = snapshot // no matching row — undo the optimistic reflect
            return false
        }
        recipes = outcome.saved // reconcile to the canonical saved scope
        await syncWriter?.enqueue(removed, type: .customRecipe, operation: .delete, baseVersion: removed.remoteVersion)
        // Nothing references the deleted row's cover anymore — clean up a local
        // `file://` orphan (delete itself ignores remote AI-cover URLs). Only
        // after a CONFIRMED persist, so a rolled-back delete keeps its cover.
        if let cover = removed.imageUrl { RecipeCoverStore.delete(cover) }
        return true
    }

    // MARK: Mutation seam

    /// Optimistic whole-scope mutation: reflects `apply` in the in-memory
    /// `recipes` immediately (instant for the detail screen, which reads it), then
    /// re-applies it to the CANONICAL scope read off the repo before the
    /// whole-scope save — so a stale in-memory list can never drop rows it didn't
    /// know about (the data-loss trap of a blind whole-scope rewrite). `apply`
    /// returns false to abort (no matching row). On a save failure restores the
    /// pre-mutation snapshot + sets `errorMessage`; on success reconciles `recipes`
    /// to the saved scope directly (no extra reload round-trip).
    private func mutate(
        apply: @Sendable @escaping (inout [Recipe]) -> Bool,
        enqueue: () async -> Void
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let snapshot = recipes
        var optimistic = recipes
        if apply(&optimistic) { recipes = optimistic } // optimistic reflect

        // Atomic load→apply→save in ONE actor hop (no suspension between the
        // canonical read and the whole-scope save), so a concurrent sync mutate
        // can't land in the window and be reverted. `nil` = no matching row (the
        // transform persisted the scope unchanged).
        let saved: [Recipe]?
        do {
            saved = try await repository.mutateRecipesReturning(householdID) { current -> ([Recipe]?, [Recipe]?) in
                var next = current
                guard apply(&next) else { return (nil, nil) } // no match → persist nothing (nil rows)
                return (next, next)
            }
        } catch {
            recipes = snapshot // rollback
            errorMessage = String(localized: "recipe.form.saveFailedRetry")
            return false
        }
        guard let saved else {
            recipes = snapshot // no matching row — undo any optimistic reflect
            return false
        }
        recipes = saved // reconcile to the canonical saved scope
        await enqueue()
        return true
    }
}
