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

    /// Appends a new recipe to the household scope, persists, enqueues a `.create`
    /// (baseVersion nil), then reloads. Returns whether the write landed.
    @discardableResult
    func add(_ recipe: Recipe) async -> Bool {
        await mutate(persist: { current in current + [recipe] }) {
            guard let patch = DomainJSON.valueMap(recipe) else { return }
            await self.syncWriter?.enqueue(
                entityType: .customRecipe,
                entityId: recipe.id,
                operation: .create,
                patch: patch,
                baseVersion: nil
            )
        }
    }

    /// Replaces the recipe with the same id in the household scope, persists,
    /// enqueues an `.update` (baseVersion = the recipe's remoteVersion), then
    /// reloads. Returns whether the write landed (false if no row matched).
    @discardableResult
    func update(_ recipe: Recipe) async -> Bool {
        await mutate(
            persist: { current in
                guard current.contains(where: { $0.id == recipe.id }) else { return nil }
                return current.map { $0.id == recipe.id ? recipe : $0 }
            },
            enqueue: {
                guard let patch = DomainJSON.valueMap(recipe) else { return }
                await self.syncWriter?.enqueue(
                    entityType: .customRecipe,
                    entityId: recipe.id,
                    operation: .update,
                    patch: patch,
                    baseVersion: recipe.remoteVersion
                )
            }
        )
    }

    /// Drops the recipe with `id` from the household scope, persists, enqueues a
    /// `.delete` (patch = the removed row so the gateway derives `deleted_at`,
    /// baseVersion = the removed row's remoteVersion), then reloads. Returns
    /// whether the write landed (false if no row matched).
    @discardableResult
    func remove(_ id: String) async -> Bool {
        var removed: Recipe?
        let ok = await mutate(
            persist: { current in
                guard let match = current.first(where: { $0.id == id }) else { return nil }
                removed = match
                return current.filter { $0.id != id }
            },
            enqueue: {
                guard let removed, let patch = DomainJSON.valueMap(removed) else { return }
                await self.syncWriter?.enqueue(
                    entityType: .customRecipe,
                    entityId: id,
                    operation: .delete,
                    patch: patch,
                    baseVersion: removed.remoteVersion
                )
            }
        )
        // Nothing references the deleted row's cover anymore — clean up a local
        // `file://` orphan (delete itself ignores remote AI-cover URLs).
        if ok, let cover = removed?.imageUrl {
            RecipeCoverStore.delete(cover)
        }
        return ok
    }

    // MARK: Mutation seam

    /// Loads the current scope, applies `persist` (returns nil to abort — no
    /// matching row), saves the WHOLE scope, enqueues the sync op, then reloads.
    /// On a save failure returns false + sets `errorMessage` (no partial write).
    private func mutate(
        persist: ([Recipe]) -> [Recipe]?,
        enqueue: () async -> Void
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let current = (try? await repository.loadAllFor(householdID)) ?? []
        guard let next = persist(current) else { return false }

        do {
            try await repository.saveRecipes(householdID, next)
        } catch {
            errorMessage = "保存失败，请重试"
            return false
        }
        await enqueue()
        await load()
        return true
    }
}
