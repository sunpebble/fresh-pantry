import Foundation

/// Household-management state machine + the activation surface for the whole sync
/// engine. The Swift port of the Flutter `HouseholdSessionController` (minus the
/// auth half, which lives in `AuthService`).
///
/// `@Observable @MainActor` so the `HouseholdView` binds directly. It owns the
/// household list / members / invite preview, drives `SyncSession.selectedHouseholdId`
/// (setting it is the ACTIVATION: the root `.task(id:)` starts pulling and the
/// writer starts enqueuing against the new scope), and re-scopes local `""` data
/// into a freshly-created household on CREATE (adoption — never on JOIN).
///
/// PARITY:
/// - `selectedHouseholdId` is set on the ROOT `SyncSession` passed in (never a
///   fresh instance — a per-screen session would silently no-op the writer).
/// - Selection-pick logic mirrors the Dart helpers
///   `_selectedHouseholdIdAfterRemoval` / `_selectedHouseholdIdAfterJoin`.
/// - Generation guard (`refreshGeneration`) mirrors `_refreshHouseholdsGeneration`
///   so a stale in-flight `refreshHouseholds` never clobbers a newer one.
/// - Every method that touches the network guards `remote` non-nil and surfaces a
///   failure as `errorMessage` rather than crashing; local-only mode is graceful.
@Observable
@MainActor
final class HouseholdSessionStore {
    private let remote: RemotePantryRepository?
    private let session: SyncSession
    private let auth: AuthService
    private let inventory: InventoryRepository
    private let shopping: ShoppingRepository
    private let customRecipe: CustomRecipeRepository
    private let mealPlan: MealPlanRepository
    /// Offline-first cache of `households` + `members` for the signed-in identity.
    /// Seeded synchronously in `init` (no onboard-form flash on a cold/offline open)
    /// and rewritten after every successful network load / mutation. nil disables
    /// caching (tests / no Application Support).
    private let householdCache: HouseholdCache?

    /// Households the signed-in user belongs to (the `households` list).
    private(set) var households: [Household] = []
    /// Members of the currently-selected household.
    private(set) var members: [HouseholdMember] = []
    /// The last previewed invite (populated by `previewInvite`, cleared on accept).
    private(set) var invitePreview: HouseholdInvitePreview?
    /// Invites addressed to the signed-in user (from `list_pending_household_invites`).
    /// Drives the "收到的邀请" reminder/list + the settings red-dot badge.
    private(set) var pendingInvitePreviews: [HouseholdInvitePreview] = []
    /// Open invites the OWNER of the selected household has issued, still unaccepted
    /// (from `list_owner_pending_invites`). Drives the owner "待处理邀请" list.
    private(set) var ownerPendingInvites: [OwnerPendingInvite] = []
    /// In-flight flag for the refresh/load reads (drives list spinners).
    private(set) var isLoading = false
    /// In-flight flag for the pending-invites refresh (kept separate from `isLoading`
    /// so it never fights the household-list spinner).
    private(set) var isPendingInvitesLoading = false
    /// In-flight flag for mutating ops (create/join/leave/dissolve/invite/etc.).
    private(set) var isSubmitting = false
    /// The last user-facing error; cleared at the start of each new attempt.
    private(set) var errorMessage: String?

    /// Monotonic counter guarding the async `refreshHouseholds` race: a newer call
    /// bumps it, so an older in-flight call's late completion is discarded.
    private var refreshGeneration = 0

    init(
        remote: RemotePantryRepository?,
        session: SyncSession,
        auth: AuthService,
        inventory: InventoryRepository,
        shopping: ShoppingRepository,
        customRecipe: CustomRecipeRepository,
        mealPlan: MealPlanRepository,
        householdCache: HouseholdCache? = nil
    ) {
        self.remote = remote
        self.session = session
        self.auth = auth
        self.inventory = inventory
        self.shopping = shopping
        self.customRecipe = customRecipe
        self.mealPlan = mealPlan
        self.householdCache = householdCache
        // OFFLINE-FIRST SEED: paint the last-known households + members for THIS
        // signed-in identity synchronously, so a cold / offline open renders the
        // real household (ActiveHouseholdSection resolves via the restored session
        // scope) instead of flashing the 「创建/加入家庭」 onboard form while
        // `refreshHouseholds()` hits the network. An identity mismatch / signed-out
        // read returns nil (never seed another user's households); the subsequent
        // refresh overwrites whatever was seeded here.
        if let snapshot = householdCache?.read(for: auth.signedInEmail) {
            households = snapshot.households
            members = snapshot.members
        }
    }

    /// True when a backend is configured (household sharing is possible).
    var isConfigured: Bool { remote != nil }

    /// The active household scope (`""` = personal / local-only).
    var selectedHouseholdId: String { session.selectedHouseholdId }

    /// The selected `Household` resolved from `households` + the session scope, or
    /// nil when nothing matches (local-only, no households, or stale id). Owning the
    /// resolution here keeps the view from re-deriving it inconsistently (mirrors
    /// the Dart `selectedHousehold` getter).
    var selectedHousehold: Household? {
        households.first { $0.id == session.selectedHouseholdId }
    }

    /// Whether the signed-in user owns the selected household (drives owner-only
    /// affordances: remove member, dissolve, rename).
    ///
    /// Resolved by matching the signed-in email against the owner member row: the
    /// local store has no user id to compare `Household.ownerId` against
    /// (`AuthService` only exposes the email), and the member list is the
    /// authoritative role source. Returns false in any unsigned / no-selection /
    /// owner-email-absent case.
    var isOwnerOfSelected: Bool {
        guard selectedHousehold != nil, let email = auth.signedInEmail else { return false }
        return members.contains { $0.role == "owner" && $0.email == email }
    }

    /// Counts in the personal (`""`) scope — used to warn before joining a
    /// household that the local data will become invisible.
    struct PersonalScopeSnapshot: Equatable, Sendable {
        let inventoryCount: Int
        let shoppingCount: Int
        let customRecipeCount: Int

        var hasData: Bool { inventoryCount + shoppingCount + customRecipeCount > 0 }

        var summaryText: String {
            var parts: [String] = []
            if inventoryCount > 0 { parts.append(String(localized: "household.personal.inventory \(inventoryCount)")) }
            if shoppingCount > 0 { parts.append(String(localized: "household.personal.shopping \(shoppingCount)")) }
            if customRecipeCount > 0 { parts.append(String(localized: "household.personal.recipes \(customRecipeCount)")) }
            return parts.joined(separator: String(localized: "household.personal.separator"))
        }
    }

    func loadPersonalScopeSnapshot() async -> PersonalScopeSnapshot {
        async let inv = (try? await inventory.loadAllFor("")) ?? []
        async let shop = (try? await shopping.loadAllFor("")) ?? []
        async let recipes = (try? await customRecipe.loadAllFor("")) ?? []
        return PersonalScopeSnapshot(
            inventoryCount: await inv.count,
            shoppingCount: await shop.count,
            customRecipeCount: await recipes.count
        )
    }

    /// True when a directed invite names a different email than the signed-in user.
    static func inviteEmailMismatch(preview: HouseholdInvitePreview, signedInEmail: String?) -> Bool {
        let invited = preview.invitedEmail.trimmed.lowercased()
        guard !invited.isEmpty else { return false }
        let signedIn = (signedInEmail ?? "").trimmed.lowercased()
        return !signedIn.isEmpty && signedIn != invited
    }

    // MARK: - Refresh

    /// Loads the user's households, picks the selected id (keep current if still
    /// joined, else the first household, else `""`), projects it onto the root
    /// session, and loads the selected household's members. Generation-guarded so a
    /// stale in-flight refresh never overwrites a newer one.
    func refreshHouseholds() async {
        guard let remote else { return }
        let generation = nextGeneration()
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await remote.loadHouseholds()
            let selectedId = Self.pickSelected(loaded, current: session.selectedHouseholdId)
            let loadedMembers = try await membersFor(remote, households: loaded, selected: selectedId)
            guard generation == refreshGeneration else { return }
            households = loaded
            session.selectedHouseholdId = selectedId
            members = loadedMembers
            persistHouseholdSnapshot()
            isLoading = false
            // Populate the invite surfaces off the same entry point Flutter uses
            // (refreshHouseholds). A signed-out refresh clears stale invites.
            if isAuthenticated {
                await refreshPendingInvites()
                await refreshOwnerPendingInvites(session.selectedHouseholdId)
            } else {
                pendingInvitePreviews = []
                ownerPendingInvites = []
            }
        } catch {
            guard generation == refreshGeneration else { return }
            isLoading = false
            errorMessage = Self.message(error)
        }
    }

    // MARK: - Create (with adoption)

    /// Creates a household, ADOPTS the personal (`""` scope) local data into it (so
    /// it becomes the household's initial content the content-sync coordinator then
    /// uploads), and selects it. Adoption runs BEFORE the selection so the rows are
    /// already under the household scope when `syncTo` fires.
    func createHousehold(name: String) async {
        guard let remote else { return }
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "household.error.nameRequired")
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            let household = try await remote.createHousehold(name: trimmed)
            // ADOPTION before selection: re-scope local-only rows into the new
            // household so the first `syncTo` uploads them as initial content.
            await adoptLocalDataIntoHousehold(household.id)
            let loaded = try await remote.loadHouseholds()
            let loadedMembers = try await membersFor(remote, households: loaded, selected: household.id)
            households = loaded
            session.selectedHouseholdId = household.id
            members = loadedMembers
            persistHouseholdSnapshot()
            isSubmitting = false
        } catch {
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    /// Moves the personal (`""` scope) local rows into the household scope so they
    /// become its initial content. Mirrors the LOCAL part of the Flutter
    /// `uploadInitialData`: re-mint non-UUID ids, `saveX(household, rows)`, then
    /// purge the `""` originals (so they don't linger as duplicate orphans later
    /// passes re-mint). Only ever called on CREATE — never on JOIN.
    ///
    /// Each step is best-effort (`try?`): a single repo failure must not abort the
    /// create flow or crash. The content-sync coordinator uploads whatever landed.
    func adoptLocalDataIntoHousehold(_ id: String) async {
        guard !id.isEmpty else { return }

        let inventoryRows = ((try? await inventory.loadAllFor("")) ?? []).map(Self.reminted)
        if !inventoryRows.isEmpty {
            try? await inventory.saveItems(id, inventoryRows)
            try? await inventory.deleteHouseholdScope("")
        }

        let shoppingRows = ((try? await shopping.loadAllFor("")) ?? []).map(Self.reminted)
        if !shoppingRows.isEmpty {
            try? await shopping.saveItems(id, shoppingRows)
            try? await shopping.deleteHouseholdScope("")
        }

        let recipeRows = ((try? await customRecipe.loadAllFor("")) ?? []).map(Self.reminted)
        if !recipeRows.isEmpty {
            try? await customRecipe.saveRecipes(id, recipeRows)
            try? await customRecipe.deleteHouseholdScope("")
        }

        let mealPlanRows = ((try? await mealPlan.loadAllFor("")) ?? []).map(Self.reminted)
        if !mealPlanRows.isEmpty {
            try? await mealPlan.saveEntries(id, mealPlanRows)
            try? await mealPlan.deleteHouseholdScope("")
        }

        // FoodLog (减废历史) moves too — otherwise the personal departure log is
        // orphaned in the `""` scope: invisible to the re-scoped stats AND never
        // uploaded (`uploadLocalOnly` only reads the household scope). The repo is
        // derived from the inventory repo's container (all repos share the one app
        // container) so the store's init — built at three view call sites — stays
        // unchanged for this adoption-only dependency.
        let foodLog = FoodLogRepository(modelContainer: inventory.modelContainer)
        let foodLogRows = ((try? await foodLog.loadAllFor("")) ?? []).map(Self.reminted)
        if !foodLogRows.isEmpty {
            try? await foodLog.saveEntries(id, foodLogRows)
            try? await foodLog.deleteHouseholdScope("")
        }

        // 收藏 / 忌口 (set-membership) move too — but their ids are DETERMINISTIC on
        // `(household, key)`, so re-mapping is a re-KEY to the new household (not the
        // random `reminted`), otherwise the adopted row keeps the `""`-scoped id and
        // a member's later favorite of the same recipe makes a DISTINCT id → a
        // duplicate. Only active marks are adopted (tombstones don't carry forward);
        // remoteVersion resets to 0 so `uploadLocalOnly` uploads them as initial
        // content. Repos derive from the shared container (init stays unchanged).
        let favorites = FavoriteRecipeRepository(modelContainer: inventory.modelContainer)
        let favoriteRows = ((try? await favorites.loadAllFor("")) ?? [])
            .filter { $0.deletedAt == nil }
            .map { FavoriteRecipe.make(householdID: id, recipeID: $0.recipeID) }
        if !favoriteRows.isEmpty {
            try? await favorites.saveEntries(id, favoriteRows)
            try? await favorites.deleteHouseholdScope("")
        }

        let dietary = DietaryPreferenceRepository(modelContainer: inventory.modelContainer)
        let dietaryRows = ((try? await dietary.loadAllFor("")) ?? [])
            .filter { $0.deletedAt == nil }
            .map { DietaryPreference.make(householdID: id, keyword: $0.keyword) }
        if !dietaryRows.isEmpty {
            try? await dietary.saveEntries(id, dietaryRows)
            try? await dietary.deleteHouseholdScope("")
        }
    }

    // MARK: - Join

    /// Previews an invite (token or share URL) and stores the result for the join
    /// confirmation. Parses the input via `InviteToken.fromInput`; an unparseable
    /// input surfaces an error and clears the preview.
    func previewInvite(input: String) async {
        guard let remote else { return }
        guard let token = InviteToken.fromInput(input) else {
            invitePreview = nil
            errorMessage = String(localized: "household.error.invalidInvite")
            return
        }
        isSubmitting = true
        errorMessage = nil
        invitePreview = nil
        do {
            invitePreview = try await remote.previewInvite(token: token)
            isSubmitting = false
        } catch {
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    /// Accepts an invite (token or share URL) and switches to the joined household.
    /// NO adoption on join — the joiner gets the household's existing content; the
    /// local `""` data stays in the personal scope (mirrors Flutter). Selects the
    /// previewed/joined household via the `_selectedHouseholdIdAfterJoin` rule.
    func acceptInvite(input: String) async {
        guard let remote else { return }
        guard let token = InviteToken.fromInput(input) else {
            errorMessage = String(localized: "household.error.invalidInvite")
            return
        }
        isSubmitting = true
        errorMessage = nil
        let preferredId = invitePreview?.householdId
        let acceptedInviteId = invitePreview?.inviteId
        // Optimistic: the accepted card disappears the instant 接受 is tapped — the
        // join is network-bound but the card removal needn't wait for it. A throw
        // rolls the prune back (the card reappears alongside the error).
        let invitesSnapshot = pendingInvitePreviews
        if let acceptedInviteId, !acceptedInviteId.isEmpty {
            pendingInvitePreviews = pendingInvitePreviews.filter { $0.inviteId != acceptedInviteId }
        }
        do {
            try await remote.acceptInvite(token: token)
            let loaded = try await remote.loadHouseholds()
            let selectedId = Self.pickJoined(
                loaded,
                preferred: preferredId,
                current: session.selectedHouseholdId
            )
            let loadedMembers = try await membersFor(remote, households: loaded, selected: selectedId)
            households = loaded
            session.selectedHouseholdId = selectedId
            members = loadedMembers
            persistHouseholdSnapshot()
            invitePreview = nil
            isSubmitting = false
            // Re-sync the received-invite list/badge so the accepted one drops
            // without waiting for the next full refresh (parity with acceptInviteById).
            await refreshPendingInvites(excludeInviteId: acceptedInviteId)
        } catch {
            pendingInvitePreviews = invitesSnapshot // rollback the optimistic prune
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    // MARK: - Pending invites (received + owner-issued)

    /// Reloads the invites addressed to the signed-in user. `excludeInviteId` drops
    /// a just-accepted invite optimistically. Spinner-silent (`isPendingInvitesLoading`
    /// only) so it never fights the household-list spinner. Mirrors the Dart
    /// `refreshPendingInvites`.
    func refreshPendingInvites(excludeInviteId: String? = nil) async {
        guard let remote else { pendingInvitePreviews = []; isPendingInvitesLoading = false; return }
        guard isAuthenticated else { pendingInvitePreviews = []; isPendingInvitesLoading = false; return }
        isPendingInvitesLoading = true
        errorMessage = nil
        do {
            let loaded = try await remote.loadPendingInvites()
            pendingInvitePreviews = excludeInviteId.map { id in loaded.filter { $0.inviteId != id } } ?? loaded
            isPendingInvitesLoading = false
        } catch {
            isPendingInvitesLoading = false
            errorMessage = Self.message(error)
        }
    }

    /// Reloads the open invites the OWNER of the selected household has issued.
    ///
    /// `list_owner_pending_invites` is an owner-only RPC — it raises 'Not authorized'
    /// for a non-owner — so the fetch is gated on ownership, the SAME condition the
    /// UI uses to render the list (`isOwner`). This mirrors the Flutter screen's
    /// `_ensureOwnerPendingInvitesLoaded(isOwner)` gate (the iOS port had folded the
    /// call into `refreshHouseholds` but dropped that gate, so a signed-in non-owner
    /// member surfaced 'Not authorized' on page load). A non-owner / signed-out /
    /// no-backend / empty-id caller just clears the list without hitting the RPC.
    func refreshOwnerPendingInvites(_ householdId: String) async {
        guard let remote, isAuthenticated, isOwnerOfSelected else {
            ownerPendingInvites = []
            return
        }
        do {
            ownerPendingInvites = try await remote.fetchOwnerPendingInvites(householdId)
        } catch {
            errorMessage = Self.message(error)
        }
    }

    /// Accepts a pending invite by its id (the inline "接受" path) and switches to
    /// the joined household. Mirrors the Dart `acceptInviteById`.
    func acceptInviteById(_ inviteId: String) async {
        guard let remote else { return }
        let trimmed = inviteId.trimmed
        guard !trimmed.isEmpty else { errorMessage = String(localized: "household.error.inviteMissing"); return }
        isSubmitting = true
        errorMessage = nil
        let preferredId = pendingInvitePreviews.first { $0.inviteId == trimmed }?.householdId
        // Optimistic: the accepted card disappears on tap; rollback on a throw.
        let invitesSnapshot = pendingInvitePreviews
        pendingInvitePreviews = pendingInvitePreviews.filter { $0.inviteId != trimmed }
        do {
            try await remote.acceptInviteById(inviteId: trimmed)
            let loaded = try await remote.loadHouseholds()
            let selectedId = Self.pickJoined(loaded, preferred: preferredId, current: session.selectedHouseholdId)
            let loadedMembers = try await membersFor(remote, households: loaded, selected: selectedId)
            households = loaded
            session.selectedHouseholdId = selectedId
            members = loadedMembers
            persistHouseholdSnapshot()
            invitePreview = nil
            isSubmitting = false
            await refreshPendingInvites(excludeInviteId: trimmed)
        } catch {
            pendingInvitePreviews = invitesSnapshot // rollback the optimistic prune
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    /// Revokes an invite the owner issued for `householdId`, then re-fetches the
    /// owner list so the revoked row disappears. Mirrors the Dart `revokeInvite`.
    func revokeInvite(householdId: String, inviteId: String) async {
        guard let remote else { return }
        isSubmitting = true
        errorMessage = nil
        // Optimistic: the invite row vanishes the instant 撤销 is tapped; the RPC
        // is the authority, so a throw rolls it back + surfaces the error.
        let snapshot = ownerPendingInvites
        ownerPendingInvites.removeAll { $0.id == inviteId }
        do {
            try await remote.revokeInvite(inviteId: inviteId)
            isSubmitting = false
            await refreshOwnerPendingInvites(householdId) // reconcile
        } catch {
            ownerPendingInvites = snapshot // rollback
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    // MARK: - Invite creation

    /// Creates an invite for the selected household and returns its share URL (or
    /// nil on failure / no selection). An optional `email` binds the invite; nil /
    /// blank yields an open link.
    @discardableResult
    func createInvite(email: String?) async -> String? {
        guard let remote else { return nil }
        let householdId = session.selectedHouseholdId
        guard !householdId.isEmpty else {
            errorMessage = String(localized: "household.error.noHouseholdSelected")
            return nil
        }
        let trimmed = email?.trimmed
        let target = (trimmed?.isEmpty ?? true) ? nil : trimmed
        isSubmitting = true
        errorMessage = nil
        do {
            let url = try await remote.createInvite(householdId: householdId, email: target)
            isSubmitting = false
            // Re-fetch the owner 待处理邀请 list so the fresh invite appears without a
            // pull-to-refresh (symmetric with `revokeInvite`'s post-success refresh;
            // the owner-gate inside no-ops it for a non-owner caller).
            await refreshOwnerPendingInvites(householdId)
            return url
        } catch {
            isSubmitting = false
            errorMessage = Self.message(error)
            return nil
        }
    }

    // MARK: - Members

    /// Removes a member from the selected household and reloads the member list.
    func removeMember(_ userId: String) async {
        guard let remote else { return }
        let householdId = session.selectedHouseholdId
        guard !householdId.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        // Optimistic: the member leaves the list immediately; the RPC (RLS /
        // owner-gated) is the authority, so a throw rolls it back + shows the error.
        let snapshot = members
        members.removeAll { $0.userId == userId }
        do {
            try await remote.removeMember(householdId: householdId, userId: userId)
            members = try await remote.loadHouseholdMembers(householdId) // reconcile
            persistHouseholdSnapshot()
            isSubmitting = false
        } catch {
            members = snapshot // rollback
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    // MARK: - Leave / dissolve

    /// Leaves the selected household (member action) and re-resolves the selection.
    /// Returns whether the leave succeeded.
    @discardableResult
    func leaveHousehold() async -> Bool {
        await removeSelf(dissolve: false)
    }

    /// Dissolves the selected household (owner-only) and re-resolves the selection.
    /// Returns whether the dissolve succeeded.
    @discardableResult
    func dissolveHousehold() async -> Bool {
        await removeSelf(dissolve: true)
    }

    /// Shared leave/dissolve path: run the RPC, reload households, pick the
    /// selection via `_selectedHouseholdIdAfterRemoval`, and reload members.
    private func removeSelf(dissolve: Bool) async -> Bool {
        guard let remote else { return false }
        let householdId = session.selectedHouseholdId
        guard !householdId.isEmpty else {
            errorMessage = String(localized: "household.error.notFound")
            return false
        }
        isSubmitting = true
        errorMessage = nil
        do {
            if dissolve {
                try await remote.dissolveHousehold(householdId)
            } else {
                try await remote.leaveHousehold(householdId)
            }
            let loaded = try await remote.loadHouseholds()
            let selectedId = Self.pickAfterRemoval(
                loaded,
                removed: householdId,
                current: session.selectedHouseholdId
            )
            let loadedMembers = try await membersFor(remote, households: loaded, selected: selectedId)
            households = loaded
            session.selectedHouseholdId = selectedId
            members = loadedMembers
            persistHouseholdSnapshot()
            // The left/dissolved household's owner invites are gone; the user may
            // now be addressed by pending invites for remaining households.
            ownerPendingInvites = []
            isSubmitting = false
            if isAuthenticated { await refreshPendingInvites() }
            return true
        } catch {
            isSubmitting = false
            errorMessage = Self.message(error)
            return false
        }
    }

    // MARK: - Switch / rename

    /// Switches the active household optimistically (sets the session scope, which
    /// activates sync for the new household) then reloads its members; rolls the
    /// selection back on a load failure (mirrors the Dart `switchHousehold`).
    func switchHousehold(_ id: String) async {
        guard let remote else { return }
        let previousId = session.selectedHouseholdId
        isLoading = true
        errorMessage = nil
        session.selectedHouseholdId = id
        do {
            members = try await remote.loadHouseholdMembers(id)
            persistHouseholdSnapshot()
            isLoading = false
            await refreshOwnerPendingInvites(id)
        } catch {
            session.selectedHouseholdId = previousId
            isLoading = false
            errorMessage = Self.message(error)
        }
    }

    /// Renames the selected household and reloads the household list so the new
    /// name shows immediately.
    func updateHouseholdName(_ name: String) async {
        guard let remote else { return }
        let householdId = session.selectedHouseholdId
        guard !householdId.isEmpty else { return }
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "household.error.nameRequired")
            return
        }
        isSubmitting = true
        errorMessage = nil
        // Optimistic: the title updates in place immediately (`selectedHousehold`
        // is computed from `households`); a throw rolls the rename back + shows it.
        let snapshot = households
        if let i = households.firstIndex(where: { $0.id == householdId }) {
            households[i].name = trimmed
        }
        do {
            try await remote.updateHouseholdName(householdId, name: trimmed)
            households = try await remote.loadHouseholds() // reconcile
            persistHouseholdSnapshot()
            isSubmitting = false
        } catch {
            households = snapshot // rollback
            isSubmitting = false
            errorMessage = Self.message(error)
        }
    }

    /// Persists the current households + members for the signed-in identity so the
    /// next launch can seed them offline-first (the cache read is identity-guarded).
    /// No-op without a cache or when signed out — a blank-email snapshot would just
    /// fail that guard. Called at the tail of every success path that reassigns
    /// `households` / `members` (incl. leave/dissolve → empty, which correctly
    /// caches "no household").
    private func persistHouseholdSnapshot() {
        guard let householdCache, let email = auth.signedInEmail?.trimmed, !email.isEmpty else { return }
        householdCache.write(.init(
            email: email,
            households: households,
            selectedHouseholdId: session.selectedHouseholdId,
            members: members
        ))
    }

    // MARK: - Helpers

    /// Whether a user is signed in — the iOS equivalent of the Flutter gateway's
    /// `isAuthenticated`. Gates the invite refreshes (configured-but-signed-out →
    /// empty lists).
    private var isAuthenticated: Bool { auth.signedInEmail != nil }

    private func nextGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    /// Loads members for the household the selection resolves to (or the first
    /// household), or `[]` when there are none. Mirrors the Dart
    /// `_loadMembersForSelectedHousehold`.
    private func membersFor(
        _ remote: RemotePantryRepository,
        households: [Household],
        selected: String
    ) async throws -> [HouseholdMember] {
        guard let first = households.first else { return [] }
        let target = (!selected.isEmpty && households.contains { $0.id == selected })
            ? selected
            : first.id
        return try await remote.loadHouseholdMembers(target)
    }

    /// Re-mints a domain row's id when it's not a canonical UUID (mirrors
    /// `uploadInitialData`'s id re-minting); a valid UUID is kept as-is.
    private static func reminted(_ item: Ingredient) -> Ingredient {
        guard !ProposalApply.isUuid(item.id) else { return item }
        var copy = item
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    private static func reminted(_ item: ShoppingItem) -> ShoppingItem {
        guard !ProposalApply.isUuid(item.id) else { return item }
        var copy = item
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    private static func reminted(_ recipe: Recipe) -> Recipe {
        guard !ProposalApply.isUuid(recipe.id) else { return recipe }
        var copy = recipe
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    private static func reminted(_ entry: MealPlanEntry) -> MealPlanEntry {
        guard !ProposalApply.isUuid(entry.id) else { return entry }
        var copy = entry
        copy.id = UUID().uuidString.lowercased()
        return copy
    }

    private static func reminted(_ entry: FoodLogEntry) -> FoodLogEntry {
        guard !ProposalApply.isUuid(entry.id) else { return entry }
        return entry.copyWith(id: FoodLogEntry.newId())
    }

    /// Selection pick on refresh: keep the current id if still joined, else the
    /// first household, else `""`. Mirrors the Dart `refreshHouseholds` logic.
    static func pickSelected(_ households: [Household], current: String) -> String {
        if !current.isEmpty, households.contains(where: { $0.id == current }) {
            return current
        }
        return households.first?.id ?? ""
    }

    /// Selection pick after a join: prefer the joined household, else keep the
    /// current if still present, else the LAST household. Mirrors
    /// `_selectedHouseholdIdAfterJoin`.
    static func pickJoined(_ households: [Household], preferred: String?, current: String) -> String {
        guard !households.isEmpty else { return "" }
        let preferredId = preferred?.trimmed ?? ""
        if !preferredId.isEmpty, households.contains(where: { $0.id == preferredId }) {
            return preferredId
        }
        if !current.isEmpty, households.contains(where: { $0.id == current }) {
            return current
        }
        return households.last?.id ?? ""
    }

    /// Selection pick after a leave/dissolve: keep the current if it wasn't removed
    /// and is still present, else the first household, else `""`. Mirrors
    /// `_selectedHouseholdIdAfterRemoval`.
    static func pickAfterRemoval(_ households: [Household], removed: String, current: String) -> String {
        guard !households.isEmpty else { return "" }
        if !current.isEmpty, current != removed, households.contains(where: { $0.id == current }) {
            return current
        }
        return households.first?.id ?? ""
    }

    /// Maps a thrown error to a user-facing message. Keeps the remote layer's
    /// typed errors readable; falls back to the localized description.
    private static func message(_ error: Error) -> String {
        switch error {
        case RemotePantryError.notSignedIn:
            return String(localized: "household.error.notSignedIn")
        case let RemotePantryError.invalidArgument(_, reason):
            return reason
        case RemotePantryError.previewUnavailable:
            return String(localized: "household.error.previewUnavailable")
        default:
            return error.localizedDescription
        }
    }
}
