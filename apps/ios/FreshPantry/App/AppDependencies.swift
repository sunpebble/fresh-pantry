import Foundation
import SwiftData

/// App-wide dependency container injected into the environment.
///
/// Holds the long-lived `@ModelActor` repositories (built once from the shared
/// `ModelContainer`) and the active household scope. Feature stores read this to
/// construct themselves, so the wiring stays in one place.
///
/// `householdID` is local-only for now (the empty-string "personal" scope);
/// real household selection / sync arrives in a later phase. This is the
/// reusable DI template every feature module will plug into.
@Observable
@MainActor
final class AppDependencies {
    let inventoryRepository: InventoryRepository
    /// Append-only food-departure log (consumed/wasted) — the waste-stats source
    /// of truth. The cook → deduction flow auto-logs consumed departures here.
    let foodLogRepository: FoodLogRepository
    /// 收藏菜谱集合(家庭同步)— `FavoritesStore` 的本地落库 + 同步源。
    let favoriteRecipeRepository: FavoriteRecipeRepository
    /// 忌口关键字集合(家庭同步)— `DietaryPreferencesStore` 的本地落库 + 同步源。
    let dietaryPreferenceRepository: DietaryPreferenceRepository
    /// Device-local per-recipe cook tally (#7) — drives 最常做/好久没做 + 做过 N 次.
    let cookHistoryRepository: CookHistoryRepository
    /// Single-row local cache of the current user's profile (avatar/name/nickname).
    let profileRepository: ProfileRepository
    /// Drives the profile-edit screen + the登录后 onboarding profile gate. Shared
    /// so Settings and the root gate read the SAME state.
    let profileStore: ProfileStore
    let shoppingRepository: ShoppingRepository
    let customRecipeRepository: CustomRecipeRepository
    /// Weekly 膳食计划 entries (one dish per LOCAL day) for the meal-plan feature.
    let mealPlanRepository: MealPlanRepository
    /// Read-only bundled HowToCook corpus loader (decoded once, cached). The
    /// offline / first-launch seed; the live source is `remoteRecipeCatalog`.
    let localRecipeRepository: LocalRecipeRepository
    /// DB-backed shared recipe catalog (Supabase `recipes` table). The live source
    /// for browse; degrades to `recipeCatalogCache` then the bundle when offline.
    let remoteRecipeCatalog: RemoteRecipeCatalog
    /// On-disk cache of the DB catalog (offline copy). nil only when Application
    /// Support is unavailable (keeps browse on bundle-only).
    let recipeCatalogCache: RecipeCatalogCache?
    /// On-disk cache of the signed-in user's households + members, so the 家庭共享
    /// screen seeds offline-first instead of flashing the onboard form while the
    /// network refresh lands. nil only when Application Support is unavailable.
    let householdCache: HouseholdCache?
    /// SwiftData cache for Open Food Facts food details + per-100g nutrition.
    /// Always built — OFF is a public API needing no backend/key.
    let foodDetailsRepository: FoodDetailsRepository
    /// Device-local barcode → product learning store (name + category by
    /// barcode). Powers the scan fast-path (local hit > OFF > manual). NOT
    /// synced — see `BarcodeMemoryRecord` for the per-device scope decision.
    let barcodeMemoryRepository: BarcodeMemoryRepository
    /// UserDefaults-backed favorites; shared so favorite state is consistent
    /// across the recipes list and detail screens.
    let favoritesStore: FavoritesStore
    /// UserDefaults-backed expiry-reminder preferences (Settings 提醒 section).
    let reminderSettingsStore: ReminderSettingsStore
    /// UserDefaults-backed 忌口 keywords (Settings 饮食偏好 section); also feeds
    /// future recipe filtering.
    let dietaryPreferencesStore: DietaryPreferencesStore
    /// UserDefaults-backed 饮食偏好 presets (高蛋白/低脂/素食/…). LOCAL-first; feeds
    /// the recommendation boost in `RecipeMatching.preferenceBoost`.
    let dietPreferenceStore: DietPreferenceStore
    /// Keychain-backed AI provider config (apiKey is a secret → SecretStore).
    let aiSettingsStore: AiSettingsStore
    /// UserDefaults-backed 外观 preference (跟随系统/浅色/深色); drives the root
    /// `preferredColorScheme` override. Device-local, excluded from backup/sync.
    let appearanceStore: AppearanceStore
    /// Pro 买断状态（StoreKit 2）。根 `.task` 里 `start()` 一次；Pro 门控读 `isPro`。
    let proStore: ProStore
    /// Holds a household-invite deep link captured by `onOpenURL` until the UI
    /// presents its preview/accept flow. Always built (no backend dependency).
    let inviteRouter: InviteRouter
    /// Holds a recipe URL handed in by the Share Extension until 食谱 can open the
    /// pre-filled 新建食谱 import form. Always built (no backend dependency).
    let recipeImportRouter: RecipeImportRouter
    /// Holds a 小组件深链(临期/今日膳食/购物/减废)captured by `onOpenURL` until
    /// `RootView`/`DashboardView` route it. Always built (no backend dependency).
    let widgetDeepLinkRouter: WidgetDeepLinkRouter
    /// Carries an ingredient name from 临期看板「→做这道菜」 to the Recipes tab (#18).
    let recipeFilterRouter: RecipeFilterRouter
    /// Holds a tapped expiry-notification id until the Dashboard pushes the 临期
    /// screen. Producer = `notificationService.onTap` (wired below); consumer =
    /// `DashboardView`. Always built (local notifications need no backend).
    let notificationTapRouter: NotificationTapRouter
    /// Maintains the Core Spotlight index (库存食材 + 食谱 surfaced in system
    /// search). Always built — Spotlight is a local system service, no backend.
    let spotlightIndexer: SpotlightIndexer
    /// Holds a tapped Spotlight result's parsed id until `RootView` routes it to
    /// the owning tab. Producer = `FreshPantryApp.onContinueUserActivity`.
    let spotlightRouter: SpotlightRouter
    /// Email-OTP auth state machine. `.localOnly` when no backend is configured
    /// (empty `Secrets.plist`); otherwise backed by Supabase. The next sync slice
    /// reads the shared `SupabaseClient` via `clientProvider`.
    let authService: AuthService
    /// Owns the single `SupabaseClient` (nil in local-only mode). The seam both
    /// auth (this slice) and the household-data sync engine (next slice) read.
    let clientProvider: SupabaseClientProvider
    /// 内置 AI 的 worker 基址（= 现有 api 域名）。
    private let apiBaseURL: URL
    /// App-root-resident sync session: the active household scope + per-install
    /// client id every store enqueues against. The SINGLE source of truth for
    /// `householdID` (see below). Injected once via `.environment` at the root.
    let syncSession: SyncSession
    /// Persistent outbox queue (offline-first write buffer). Local mutations are
    /// recorded here via `syncWriter`; the coordinator drains it to the backend.
    let syncOutboxRepository: SyncOutboxRepository
    /// READ + household-management half of the sync engine; nil in local-only mode.
    let remotePantryRepository: RemotePantryRepository?
    /// Drives outbox push without overlapping runs; nil in local-only mode.
    let syncCoordinator: SyncCoordinator?
    /// Local⇄remote content reconciliation engine (the "reads flow in" half):
    /// uploads local-only rows, subscribes to realtime, and merges remote rows
    /// with still-pending local ones. nil in local-only mode (no backend).
    let householdContentSync: HouseholdContentSyncCoordinator?
    /// The single seam every mutating store/controller uses to record an outbox
    /// op + kick a push. In local-only mode it records ops (no coordinator → no
    /// push) so writes flush once a backend / household is wired.
    let syncWriter: SyncWriter
    /// The single `NotificationService` instance (delegate of the shared
    /// notification center). Exposed so tests can drive the tap chain; app code
    /// schedules through `notificationCoordinator` instead.
    let notificationService: NotificationService
    /// Drives local expiry-reminder notifications (permission + scheduling).
    /// Always built — local notifications need no backend; gated only by the OS
    /// permission grant inside the service.
    let notificationCoordinator: NotificationCoordinator
    /// 诊断/可观测性门面。按构建配置分流(DEBUG→OSLog、Release+配置→Sentry、
    /// 否则→Noop)。注入到同步等关键 service;未注入处用 NoopDiagnostics 默认值。
    let diagnostics: Diagnostics

    /// The active household scope. COMPUTED from `syncSession` so the session is
    /// the single source of truth (no call site writes this); the `householdID`
    /// init param seeds the session's initial scope.
    var householdID: String { syncSession.selectedHouseholdId }

    /// 应用唯一的持久化容器(供 app 侧算小组件快照写入 App Group;widget 时间线
    /// 只读那份快照,不再自己开容器)。
    let modelContainer: ModelContainer

    init(
        modelContainer: ModelContainer,
        householdID: String = "",
        config: AppConfig? = nil,
        syncSession: SyncSession? = nil
    ) {
        self.modelContainer = modelContainer
        self.inventoryRepository = InventoryRepository(modelContainer: modelContainer)
        self.foodLogRepository = FoodLogRepository(modelContainer: modelContainer)
        self.favoriteRecipeRepository = FavoriteRecipeRepository(modelContainer: modelContainer)
        self.dietaryPreferenceRepository = DietaryPreferenceRepository(modelContainer: modelContainer)
        self.cookHistoryRepository = CookHistoryRepository(modelContainer: modelContainer)
        self.profileRepository = ProfileRepository(modelContainer: modelContainer)
        self.shoppingRepository = ShoppingRepository(modelContainer: modelContainer)
        self.customRecipeRepository = CustomRecipeRepository(modelContainer: modelContainer)
        self.mealPlanRepository = MealPlanRepository(modelContainer: modelContainer)
        self.localRecipeRepository = LocalRecipeRepository()
        self.foodDetailsRepository = FoodDetailsRepository(modelContainer: modelContainer)
        self.barcodeMemoryRepository = BarcodeMemoryRepository(modelContainer: modelContainer)
        self.reminderSettingsStore = ReminderSettingsStore()
        self.dietPreferenceStore = DietPreferenceStore()
        self.aiSettingsStore = AiSettingsStore(secrets: KeychainStore())
        self.appearanceStore = AppearanceStore()
        self.proStore = ProStore()
        self.inviteRouter = InviteRouter()
        self.recipeImportRouter = RecipeImportRouter()
        self.widgetDeepLinkRouter = WidgetDeepLinkRouter()
        self.recipeFilterRouter = RecipeFilterRouter()
        let notificationTapRouter = NotificationTapRouter()
        self.notificationTapRouter = notificationTapRouter
        self.spotlightIndexer = SpotlightIndexer()
        self.spotlightRouter = SpotlightRouter()
        let notificationService = NotificationService()
        // NOTIFICATION TAP → ROUTER: installed here (not in a view) so a
        // cold-start tap is captured as soon as the center delegate is live —
        // `didReceive` can arrive before any view exists. The handler runs on
        // the main actor (see `NotificationService.handleTap`); capturing the
        // router rather than `self` avoids a container↔service retain cycle.
        notificationService.setOnTap { id in notificationTapRouter.capture(id: id) }
        self.notificationService = notificationService
        self.notificationCoordinator = NotificationCoordinator(
            service: notificationService,
            idsRepo: ScheduledNotificationIdsRepo(),
            inventory: self.inventoryRepository,
            reminderSettings: self.reminderSettingsStore
        )
        let diagnostics = DiagnosticsFactory.make(sentryConfig: config?.sentry)
        self.diagnostics = diagnostics
        let clientProvider = SupabaseClientProvider(config: config)
        self.clientProvider = clientProvider
        self.apiBaseURL = config?.backend.apiBaseURL ?? BackendConfig.defaultAPIBaseURL
        self.authService = AuthService(backend: clientProvider.authBackend)
        // Shared recipe catalog: DB source (anon-readable `recipes` table) + the
        // on-disk offline cache. Browse reads cache-or-bundle instantly, then
        // refreshes from the DB in the background (see `RecipesStore`). UI tests
        // run HERMETIC (bundle-only): a nil client disables the network refresh so
        // the explore corpus is deterministic and can't shift mid-test.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        self.remoteRecipeCatalog = RemoteRecipeCatalog(client: isUITesting ? nil : clientProvider.client)
        self.recipeCatalogCache = RecipeCatalogCache()
        self.householdCache = HouseholdCache()

        // The app root injects the shared session; absent one (tests / previews)
        // seed a fresh session from the `householdID` param.
        let session = syncSession ?? SyncSession(selectedHouseholdId: householdID)
        self.syncSession = session

        let outbox = SyncOutboxRepository(modelContainer: modelContainer)
        self.syncOutboxRepository = outbox

        // With a backend: wire the push engine (gateway → coordinator) + the
        // read/household-management repository. Without one (local-only), the
        // writer still records ops but has no coordinator to push them.
        if let client = clientProvider.client {
            let gateway = SupabaseSyncGateway(client: client, diagnostics: diagnostics)
            let coordinator = SyncCoordinator(outbox: outbox, remote: gateway, diagnostics: diagnostics)
            self.syncCoordinator = coordinator
            let remoteRepository = RemotePantryRepository(
                client: client,
                apiBaseURL: (config?.backend.apiBaseURL ?? BackendConfig.defaultAPIBaseURL).absoluteString
            )
            self.remotePantryRepository = remoteRepository
            self.syncWriter = SyncWriter(outbox: outbox, coordinator: coordinator, session: session, diagnostics: diagnostics)
            self.householdContentSync = HouseholdContentSyncCoordinator(
                remote: remoteRepository,
                push: coordinator,
                outbox: outbox,
                inventory: self.inventoryRepository,
                shopping: self.shoppingRepository,
                customRecipe: self.customRecipeRepository,
                mealPlan: self.mealPlanRepository,
                foodLog: self.foodLogRepository,
                favoriteRecipe: self.favoriteRecipeRepository,
                dietaryPreference: self.dietaryPreferenceRepository,
                session: session,
                diagnostics: diagnostics
            )
        } else {
            self.syncCoordinator = nil
            self.remotePantryRepository = nil
            self.syncWriter = SyncWriter(outbox: outbox, coordinator: nil, session: session, diagnostics: diagnostics)
            self.householdContentSync = nil
        }
        // 收藏 / 忌口 集合恒走仓库支撑 + 家庭同步:本地模式下 session 域为 ""、
        // syncWriter 只记录 outbox 不推送(待接入后端后随首个 syncTo 上传)。需要在
        // session + syncWriter 就绪后构造,故置于此处而非前段。
        self.favoritesStore = FavoritesStore(
            repository: self.favoriteRecipeRepository,
            session: session,
            syncWriter: self.syncWriter
        )
        self.dietaryPreferencesStore = DietaryPreferencesStore(
            repository: self.dietaryPreferenceRepository,
            session: session,
            syncWriter: self.syncWriter
        )

        // Built last so it can read the (optional) remote repository regardless of
        // which backend branch ran. `RemotePantryRepository` conforms to
        // `ProfileRemote`; local-only mode passes nil (store degrades to local).
        self.profileStore = ProfileStore(
            remote: self.remotePantryRepository,
            local: self.profileRepository
        )
    }

    /// 内置 AI chat 闭包工厂；本地模式（无 Supabase 后端）返回 nil。
    func builtInAiChatFn(responseFormat: [String: JSONValue]? = nil) -> AiChatFn? {
        guard clientProvider.client != nil else { return nil }
        return AiChatAccess.builtInChatFn(
            clientProvider: clientProvider,
            apiBaseURL: apiBaseURL,
            responseFormat: responseFormat
        )
    }
}
