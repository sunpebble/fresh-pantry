import SwiftUI

/// Root navigation surface.
///
/// Uses a `TabView` with the sidebar-adaptable style so the same declaration
/// renders as a bottom tab bar on iPhone and an adaptive sidebar/tab layout on
/// iPad. The five sections mirror the existing app's primary navigation; each
/// is a placeholder until its feature module is migrated.
struct RootView: View {
    /// The five primary sections. `rawValue` doubles as a stable selection key.
    enum Section: String, Hashable, CaseIterable {
        case home, inventory, recipes, shopping, settings
    }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(InviteRouter.self) private var inviteRouter
    @Environment(RecipeImportRouter.self) private var recipeImportRouter
    @Environment(RecipeFilterRouter.self) private var recipeFilterRouter
    @Environment(NotificationTapRouter.self) private var notificationTapRouter
    @Environment(SpotlightRouter.self) private var spotlightRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Section = RootView.initialSelection()
    /// Reactive reachability for the offline / 待同步 banner.
    @State private var connectivity = ConnectivityMonitor()
    /// Best-effort outbox depth — refreshed at natural sync moments (foreground,
    /// remote merge, coming back online). The offline flag is fully reactive.
    @State private var pendingCount = 0
    /// Dead-lettered (repeatedly-failed) op count from the push coordinator —
    /// refreshed alongside `pendingCount` so the banner can say 「N 条同步失败」
    /// instead of an eternal 「同步中」 when a poison op is quarantined.
    @State private var failedCount = 0
    /// User-facing notice for an invite deep link that can't be presented yet
    /// (signed out → 请先登录; local-only → 不支持). nil = no alert.
    @State private var inviteNotice: String?
    /// Per-row 「待同步」 visibility: the set of entityIDs with a queued outbox op,
    /// shared down to the 库存 / 购物 lists. Refreshed at the SAME moments as
    /// `pendingCount` so the global banner and the per-row badges never disagree.
    @State private var pendingSync: PendingSyncStatusStore?
    /// Cross-tab nav intent: a canonical food category the 首页 grid tapped, to be
    /// consumed by the 库存 tab (preset its category filter). Cleared on consume.
    @State private var pendingCategory: String?
    /// Spotlight deep-link intent: the ingredient id whose detail the 库存 tab
    /// should push. Cleared on consume (same ownership model as `pendingCategory`).
    @State private var pendingIngredientID: String?
    /// Spotlight deep-link intent: the recipe id whose detail the 食谱 tab should
    /// push. Cleared on consume.
    @State private var pendingRecipeID: String?
    /// Cross-tab intent: preset the 食谱 tab (e.g. 用临期). Cleared on consume.
    @State private var pendingRecipesTab: RecipesStore.Tab?
    /// Cross-tab intent: scroll/highlight a shopping row after global search.
    @State private var pendingShoppingItemID: String?
    /// Presents the global search overlay (launched from the 首页 toolbar).
    @State private var showSearch = false
    /// Dead-letter detail sheet (tapped from the sync-failure banner).
    @State private var showSyncFailureSheet = false
    @State private var deadLetterItems: [DeadLetterDisplayItem] = []
    /// Drives the post-login onboarding profile cover (forces a display name).
    @State private var profileGateReady = false

    var body: some View {
        // Snapshot/test hook: `-initialRoute login` renders LoginView standalone
        // so the auth screen can be captured without driving the tab UI.
        if RootView.initialRoute() == "login" {
            NavigationStack {
                LoginView(auth: dependencies.authService)
            }
            .tint(.fkPrimary)
        } else {
            VStack(spacing: 0) {
                SyncStatusBanner(
                    isOnline: connectivity.isOnline,
                    pendingCount: pendingCount,
                    failedCount: failedCount,
                    onFailedTap: failedCount > 0 ? { Task { await presentSyncFailures() } } : nil
                )
                tabs
            }
            .sheet(isPresented: $showSearch) {
                GlobalSearchView(
                    onSelectShopping: { itemID in
                        showSearch = false
                        pendingShoppingItemID = itemID
                        selection = .shopping
                    }
                )
            }
            .sheet(isPresented: $showSyncFailureSheet) {
                SyncFailureSheet(
                    items: deadLetterItems,
                    onRetry: {
                        Task {
                            await dependencies.syncCoordinator?.pushPending()
                            await refreshPendingCount()
                        }
                    },
                    onClear: {
                        Task {
                            await dependencies.syncCoordinator?.clearDeadLetters()
                            await refreshPendingCount()
                        }
                    }
                )
            }
            // Deep-link invite: present the preview/accept sheet once the user is
            // signed in. If signed-out, the token stays pending and re-fires after
            // login (this binding re-evaluates on the signed-in change).
            .sheet(item: invitePreviewBinding) { route in
                InvitePreviewSheet(input: route.input)
            }
            // Deep-link invite FEEDBACK for the states the sheet can't cover:
            // signed out → explain + keep the token (the sheet auto-presents
            // after login); local-only → explain + drop the token (it can never
            // be processed). `.task(id:)` — not `.onChange` — so a cold-start
            // capture that landed before this view appeared still gets feedback.
            // The COMPOSITE key re-runs the gate when the Keychain restore
            // settles or the signed-in identity changes: a cold-start link no
            // longer races `restore()` into a wrong 「请先登录」 — the gate holds
            // (`.none`, token kept) until the session question is answered.
            .task(id: inviteGateKey) {
                switch InviteRouter.gateOutcome(
                    hasPendingInvite: inviteRouter.pendingInput != nil,
                    sessionResolved: dependencies.authService.hasResolvedSession,
                    isLocalOnly: dependencies.authService.state == .localOnly,
                    isSignedIn: dependencies.authService.signedInEmail != nil
                ) {
                case .none:
                    break
                case .presentPreview:
                    // The preview sheet presents on this same state flip (via
                    // invitePreviewBinding) — clear any stale 「请先登录」 alert
                    // so the two never stack with contradictory copy.
                    inviteNotice = nil
                case .promptSignIn:
                    inviteNotice = "收到家庭邀请,请先在「设置 → 家庭共享」登录,登录后会自动继续处理。"
                case .unsupported:
                    inviteNotice = "此版本未配置后端,无法打开家庭邀请。"
                    inviteRouter.clear()
                }
            }
            .alert("家庭邀请", isPresented: inviteNoticeBinding) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(inviteNotice ?? "")
            }
        }
    }

    /// Presents the onboarding profile cover when load resolved + a display name
    /// is still missing. Read-only setter (the cover dismisses by the store's
    /// state flipping, never by user cancel).
    private var profileSetupBinding: Binding<Bool> {
        Binding(
            get: { profileGateReady && dependencies.profileStore.needsProfileSetup },
            set: { _ in }
        )
    }

    /// Drives the invite-notice alert; dismissing clears the message.
    private var inviteNoticeBinding: Binding<Bool> {
        Binding(
            get: { inviteNotice != nil },
            set: { if !$0 { inviteNotice = nil } }
        )
    }

    /// Composite trigger for the invite-gate `.task(id:)`: a newly captured
    /// token, the Keychain session restore settling (`hasResolvedSession`), or
    /// a signed-in identity change each re-evaluate the gate. Same string-key
    /// pattern as `householdRevisionKey`. Never logged (the input is a bearer
    /// token — `InviteRouter`'s no-log rule applies).
    private var inviteGateKey: String {
        let auth = dependencies.authService
        return "\(inviteRouter.pendingInput ?? "")#\(auth.hasResolvedSession)#\(auth.signedInEmail ?? "")"
    }

    /// Drives the deep-link invite sheet: presents only when a token is pending AND
    /// the user is signed in; dismissing clears the router.
    private var invitePreviewBinding: Binding<InvitePreviewRoute?> {
        Binding(
            get: {
                guard let input = inviteRouter.pendingInput,
                      dependencies.authService.signedInEmail != nil else { return nil }
                return InvitePreviewRoute(input: input)
            },
            set: { newValue in if newValue == nil { inviteRouter.clear() } }
        )
    }

    /// Best-effort refresh of the outbox depth shown in the banner AND the
    /// per-row 「待同步」 set behind the list badges — kept on the same trigger so
    /// the global count and the per-row badges stay consistent. The per-row store
    /// is seeded once in the `.task` below; until then this is a no-op for it.
    @MainActor
    private func refreshPendingCount() async {
        pendingCount = (try? await dependencies.syncOutboxRepository.loadPending().count) ?? 0
        failedCount = await dependencies.syncCoordinator?.deadLetterCount ?? 0
        await pendingSync?.refresh()
    }

    @MainActor
    private func presentSyncFailures() async {
        let pending = (try? await dependencies.syncOutboxRepository.loadPending()) ?? []
        deadLetterItems = await dependencies.syncCoordinator?
            .deadLetterDisplayItems(pending: pending) ?? []
        showSyncFailureSheet = true
    }

    /// Composite content-sync trigger: fires when the Keychain restore settles,
    /// the signed-in identity changes, or the household switches — so the
    /// launch-restored scope starts syncing once (and only once) the session is
    /// authenticated. Same string-key pattern as `inviteGateKey`.
    private var contentSyncKey: String {
        let auth = dependencies.authService
        return "\(auth.hasResolvedSession)#\(auth.signedInEmail ?? "")#\(dependencies.syncSession.selectedHouseholdId)"
    }

    /// Composite auto-select trigger: the Keychain restore settling and the
    /// signed-in identity each re-evaluate household selection. Keying on the
    /// email alone would never re-fire for a signed-out launch (nil → nil).
    private var authSelectionKey: String {
        let auth = dependencies.authService
        return "\(auth.hasResolvedSession)#\(auth.signedInEmail ?? "")"
    }

    /// Composite household-content trigger: fires on household switch AND on
    /// every remote-merge pulse (plus once on appear, covering launch). Drives
    /// both the Spotlight rebuild and the expiry-reminder reschedule, so
    /// neither tracks a stale household scope or stale merged rows.
    private var householdRevisionKey: String {
        "\(dependencies.syncSession.selectedHouseholdId)#\(dependencies.syncSession.dataRevision)"
    }

    /// Rebuilds both Spotlight domains from the active household's rows. A
    /// failed load SKIPS that domain's rebuild (keeping the last good index)
    /// rather than wiping it with an empty list. Index errors themselves are
    /// logged + swallowed inside the indexer (Spotlight is an enhancement, not
    /// a core path). Local-only mutations don't pulse `dataRevision`, so the
    /// index can lag until the next launch/sync — accepted: Spotlight is a
    /// re-engagement entry point, not a live mirror.
    @MainActor
    private func reindexSpotlight() async {
        let householdID = dependencies.syncSession.selectedHouseholdId
        let indexer = dependencies.spotlightIndexer
        if let inventory = try? await dependencies.inventoryRepository.loadAllFor(householdID) {
            await indexer.reindexInventory(inventory)
        }
        if let custom = try? await dependencies.customRecipeRepository.loadAllFor(householdID) {
            let bundled = await dependencies.localRecipeRepository.loadAll()
            await indexer.reindexRecipes(RecipesStore.merge(bundled: bundled, custom: custom))
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("首页", systemImage: "house", value: Section.home) {
                DashboardView(
                    onSelectShopping: { selection = .shopping },
                    onSelectCategory: { category in
                        pendingCategory = category
                        selection = .inventory
                    },
                    onSearch: { showSearch = true },
                    onSelectExpiringRecipes: {
                        pendingRecipesTab = .expiring
                        selection = .recipes
                    }
                )
            }
            Tab("库存", systemImage: "tray.full", value: Section.inventory) {
                InventoryView(
                    pendingCategory: $pendingCategory,
                    pendingIngredientID: $pendingIngredientID
                )
            }
            Tab("食谱", systemImage: "book", value: Section.recipes) {
                RecipesView(
                    pendingRecipeID: $pendingRecipeID,
                    pendingRecipesTab: $pendingRecipesTab
                )
            }
            Tab("购物", systemImage: "cart", value: Section.shopping) {
                ShoppingView(pendingItemID: $pendingShoppingItemID)
            }
            Tab("设置", systemImage: "gearshape", value: Section.settings) {
                SettingsView(
                    onSelectCategory: { category in
                        pendingCategory = category
                        selection = .inventory
                    },
                    onSelectExpiringRecipes: {
                        pendingRecipesTab = .expiring
                        selection = .recipes
                    }
                )
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // SHARE the per-row sync-status store down to the 库存 / 购物 lists. Seeded
        // in the `.task` below (not here) so building it from the live outbox
        // actor never mutates @State during a body pass. Optional → descendants
        // read nil for the first frame (no badge), then the seeded store.
        .environment(pendingSync)
        // POST-LOGIN ONBOARDING: force a display name once signed in. The cover
        // shows only after profile load resolved (profileGateReady) AND the store
        // reports needsProfileSetup; saving a name flips it false → auto-dismiss.
        .fullScreenCover(isPresented: profileSetupBinding) {
            ProfileEditView(store: dependencies.profileStore, mode: .onboarding)
        }
        // SEED the per-row sync-status store once from the outbox actor, then do
        // the first read so badges reflect any startup backlog. Idempotent. Also
        // hands the push coordinator the live reachability probe so dead-letter
        // strikes only count while online (an offline failure is transient).
        .task {
            if pendingSync == nil {
                pendingSync = PendingSyncStatusStore(outbox: dependencies.syncOutboxRepository)
            }
            await pendingSync?.refresh()
            let monitor = connectivity
            await dependencies.syncCoordinator?.setOnlineProbe {
                await MainActor.run { monitor.isOnline }
            }
        }
        // DRIVE CONTENT SYNC: reconcile local⇄remote for the selected household.
        // Re-runs on every household switch / auth settle (and once on launch);
        // the coordinator no-ops when the household is unchanged. nil in
        // local-only mode. GATED ON A SIGNED-IN RESOLVED SESSION for a non-empty
        // id: the scope is now restored from UserDefaults at launch, and an
        // unauthenticated bulk pull would come back RLS-empty — the merge keeps
        // only never-synced local rows, so it would WIPE every synced row.
        .task(id: contentSyncKey) {
            let auth = dependencies.authService
            guard auth.hasResolvedSession else { return }
            guard auth.signedInEmail != nil else {
                await dependencies.householdContentSync?.syncTo("")
                return
            }
            await dependencies.householdContentSync?
                .syncTo(dependencies.syncSession.selectedHouseholdId)
        }
        // FOREGROUND FLUSH + RESCHEDULE: on every return to the foreground drain
        // the outbox (the dependable push path — background sync is throttled on
        // iOS) and recompute expiry reminders so they reflect the latest
        // inventory / settings without waiting for a Settings change.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                // Re-run a failed inbound sync first (no-op when the last run
                // succeeded), then drain the outbox and the pending profile
                // upload (idempotent; no-op without a queued avatar/name).
                await dependencies.householdContentSync?.retryIfNeeded()
                await dependencies.householdContentSync?.refreshDelta()
                await dependencies.syncCoordinator?.pushPending()
                await refreshPendingCount()
                await dependencies.profileStore.retryPendingUpload()
                dependencies.syncSession.bumpInviteRefresh()
            }
            Task {
                await dependencies.notificationCoordinator
                    .reschedule(householdID: dependencies.householdID)
            }
        }
        // Refresh the banner's outbox depth when a remote merge lands or the count
        // may have changed (initial appear), and flush + recount when the device
        // comes back online so an offline backlog drains visibly.
        .task { await refreshPendingCount() }
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await refreshPendingCount() }
        }
        // An outbound push finished (SyncWriter pulse): re-read the outbox so a
        // just-synced row's 待同步 badge clears without waiting for a foreground
        // round-trip. Lighter than dataRevision — refreshes only the badges.
        .onChange(of: dependencies.syncSession.pendingSyncRevision) {
            Task { await refreshPendingCount() }
        }
        .onChange(of: connectivity.isOnline) { _, online in
            guard online else { return }
            Task {
                // INBOUND first: an offline launch's failed `startSync` left the
                // session with no bulk pull / realtime — retry it now (no-op when
                // the last run completed). Then the outbound drain + the pending
                // profile upload.
                await dependencies.householdContentSync?.retryIfNeeded()
                await dependencies.householdContentSync?.refreshDelta()
                await dependencies.syncCoordinator?.pushPending()
                await refreshPendingCount()
                await dependencies.profileStore.retryPendingUpload()
            }
        }
        // Share-extension recipe import: switch to the 食谱 tab so RecipesView
        // consumes the pending URL and opens the pre-filled 新建食谱.
        .onChange(of: recipeImportRouter.pendingURL) { _, url in
            if url != nil { selection = .recipes }
        }
        // 临期→做这道菜 (#18): switch to the 食谱 tab so RecipesView consumes the
        // pending ingredient and filters to dishes that use it.
        .onChange(of: recipeFilterRouter.pendingIngredient) { _, name in
            if name != nil { selection = .recipes }
        }
        // Spotlight result tap: switch to the owning tab and hand it the model
        // id (the tab pushes the detail). `.task(id:)` — not `.onChange` — so a
        // cold-start tap captured before this view appeared is still consumed.
        // Consuming HERE is safe (unlike the notification-tap case) because the
        // pending-…ID binding persists the intent until the tab applies it.
        .task(id: spotlightRouter.pendingItem) {
            guard let item = spotlightRouter.consume() else { return }
            switch item {
            case .ingredient(let id):
                pendingIngredientID = id
                selection = .inventory
            case .recipe(let id):
                pendingRecipeID = id
                selection = .recipes
            }
        }
        // SPOTLIGHT INDEX + REMINDER RESCHEDULE: rebuild on launch, on household
        // switch, and after every remote-merge pulse (dataRevision). The 500 ms
        // sleep is the debounce — `.task(id:)` cancels the in-flight task on each
        // pulse, so a burst of revisions coalesces into a single rebuild of the
        // final state. Whole-domain rebuilds also guarantee a household switch
        // drops the previous household's entries from the index — and the full
        // reschedule drops the previous scope's reminders the same way.
        .task(id: householdRevisionKey) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reindexSpotlight()
            await dependencies.notificationCoordinator
                .reschedule(householdID: dependencies.householdID)
        }
        // Notification tap (临期提醒/每日汇总): switch to 首页 so DashboardView —
        // the consumer — pushes the 临期 screen. Deliberately NOT consumed here:
        // a cold-start tap can be captured before this view exists (no onChange
        // fires, but the initial selection is already 首页), so the Dashboard's
        // `.task(id:)` is the one guaranteed reader. This onChange only covers
        // the "app already open on another tab" case.
        .onChange(of: notificationTapRouter.pendingTap) { _, id in
            if id != nil { selection = .home }
        }
        // RESTORE SESSION ON LAUNCH: rehydrate a persisted login from the Keychain
        // so a returning member is signed in (and sync starts) without first
        // opening the login screen. No-op in local-only mode or when already
        // signed in. Runs before the auth-driven auto-select below picks the
        // household, so the households query carries the restored JWT (avoiding the
        // verify→immediate-query token-propagation race of a fresh sign-in).
        .task {
            // UI tests launch signed-out + local-only for deterministic seeded
            // data — skip restoring a persisted Keychain session that would
            // re-scope the app to an empty synced household.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return }
            await dependencies.authService.restore()
        }
        // AUTO-SELECT HOUSEHOLD ON SIGN-IN: mirrors Flutter's AuthGate projecting
        // the session's active household into `selectedHouseholdId`, so sync starts
        // right after login instead of only once the 家庭共享 screen is opened.
        // Re-runs when the Keychain restore settles or the signed-in identity
        // changes (incl. nil → email). Bails while the restore is still in
        // flight: the launch-transient nil email must not clobber the
        // UserDefaults-restored household scope (offline-first launch); a
        // RESOLVED signed-out state still resets + persists `""` below.
        .task(id: authSelectionKey) {
            guard dependencies.authService.hasResolvedSession else { return }
            guard dependencies.authService.signedInEmail != nil else {
                profileGateReady = false
                // SIGN-OUT (or signed-out launch — both writes are idempotent
                // no-ops then): reset the enqueue scope SYNCHRONOUSLY so local
                // edits stop queueing against the old household (SyncWriter
                // guards on a non-empty id) — the root `.task(id:
                // selectedHouseholdId)` follows with `syncTo("")` — then stop
                // the content engine directly so realtime unsubscribes without
                // waiting for that task hop. Mirrors Flutter's authStateChanges
                // → refreshHouseholds → empty-selection chain.
                dependencies.syncSession.selectedHouseholdId = ""
                await dependencies.householdContentSync?.stop()
                return
            }
            // Ensure the SDK session is resolved so the households query carries the
            // user JWT (else it silently runs as anon → RLS-empty → no household).
            await dependencies.clientProvider.ensureSessionReady()
            let store = HouseholdSessionStore(
                remote: dependencies.remotePantryRepository,
                session: dependencies.syncSession,
                auth: dependencies.authService,
                inventory: dependencies.inventoryRepository,
                shopping: dependencies.shoppingRepository,
                customRecipe: dependencies.customRecipeRepository,
                mealPlan: dependencies.mealPlanRepository,
                householdCache: dependencies.householdCache
            )
            await store.refreshHouseholds()
            await dependencies.profileStore.load(signedIn: true)
            profileGateReady = true
        }
        #if DEBUG
        // Automation hooks for the live-sync verification (no UI typing on the
        // simulator): `-debugAuthEmail <e>` sends an OTP; `-debugAuthVerify <e>
        // -debugAuthCode <c>` verifies it and signs in (the auto-select task then
        // starts the pull). Inert unless the args are present.
        .task {
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            if let email = value("-debugAuthEmail") {
                await dependencies.authService.sendCode(email: email)
            } else if let email = value("-debugAuthVerify"), let code = value("-debugAuthCode") {
                await dependencies.authService.debugVerify(email: email, code: code)
            }
        }
        #endif
    }

    /// Honors a `-initialTab <section>` launch argument (used by UI snapshots /
    /// tests); defaults to 首页.
    private static func initialSelection() -> Section {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-initialTab"),
              index + 1 < ProcessInfo.processInfo.arguments.count,
              let section = Section(rawValue: ProcessInfo.processInfo.arguments[index + 1])
        else { return .home }
        return section
    }

    /// Honors a `-initialRoute <route>` launch argument (snapshot/test hook);
    /// `login` renders `LoginView` standalone. Returns nil otherwise.
    private static func initialRoute() -> String? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-initialRoute"),
              index + 1 < ProcessInfo.processInfo.arguments.count
        else { return nil }
        return ProcessInfo.processInfo.arguments[index + 1]
    }
}

#Preview {
    let container = try! ModelContainerFactory.makeInMemory()
    RootView()
        .modelContainer(container)
        .environment(AppDependencies(modelContainer: container))
}
