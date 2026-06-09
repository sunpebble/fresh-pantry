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
    let shoppingRepository: ShoppingRepository
    let customRecipeRepository: CustomRecipeRepository
    /// Weekly 膳食计划 entries (one dish per LOCAL day) for the meal-plan feature.
    let mealPlanRepository: MealPlanRepository
    /// Read-only bundled HowToCook corpus loader (decoded once, cached).
    let localRecipeRepository: LocalRecipeRepository
    /// SwiftData cache for Open Food Facts food details + per-100g nutrition.
    /// Always built — OFF is a public API needing no backend/key.
    let foodDetailsRepository: FoodDetailsRepository
    /// Best-effort OFF lookup client (barcode-first, then name search). The DI
    /// seam the ingredient-detail nutrition card builds its store from.
    let foodDetailsClient: FoodDetailsClient
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
    /// Holds a household-invite deep link captured by `onOpenURL` until the UI
    /// presents its preview/accept flow. Always built (no backend dependency).
    let inviteRouter: InviteRouter
    /// Holds a recipe URL handed in by the Share Extension until 食谱 can open the
    /// pre-filled 新建食谱 import form. Always built (no backend dependency).
    let recipeImportRouter: RecipeImportRouter
    /// Email-OTP auth state machine. `.localOnly` when no backend is configured
    /// (empty `Secrets.plist`); otherwise backed by Supabase. The next sync slice
    /// reads the shared `SupabaseClient` via `clientProvider`.
    let authService: AuthService
    /// Owns the single `SupabaseClient` (nil in local-only mode). The seam both
    /// auth (this slice) and the household-data sync engine (next slice) read.
    let clientProvider: SupabaseClientProvider
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
    /// Drives local expiry-reminder notifications (permission + scheduling).
    /// Always built — local notifications need no backend; gated only by the OS
    /// permission grant inside the service.
    let notificationCoordinator: NotificationCoordinator

    /// The active household scope. COMPUTED from `syncSession` so the session is
    /// the single source of truth (no call site writes this); the `householdID`
    /// init param seeds the session's initial scope.
    var householdID: String { syncSession.selectedHouseholdId }

    init(
        modelContainer: ModelContainer,
        householdID: String = "",
        config: AppConfig? = nil,
        syncSession: SyncSession? = nil
    ) {
        self.inventoryRepository = InventoryRepository(modelContainer: modelContainer)
        self.foodLogRepository = FoodLogRepository(modelContainer: modelContainer)
        self.shoppingRepository = ShoppingRepository(modelContainer: modelContainer)
        self.customRecipeRepository = CustomRecipeRepository(modelContainer: modelContainer)
        self.mealPlanRepository = MealPlanRepository(modelContainer: modelContainer)
        self.localRecipeRepository = LocalRecipeRepository()
        self.foodDetailsRepository = FoodDetailsRepository(modelContainer: modelContainer)
        self.foodDetailsClient = OpenFoodFactsDetailsClient()
        self.favoritesStore = FavoritesStore()
        self.reminderSettingsStore = ReminderSettingsStore()
        self.dietaryPreferencesStore = DietaryPreferencesStore()
        self.dietPreferenceStore = DietPreferenceStore()
        self.aiSettingsStore = AiSettingsStore(secrets: KeychainStore())
        self.appearanceStore = AppearanceStore()
        self.inviteRouter = InviteRouter()
        self.recipeImportRouter = RecipeImportRouter()
        self.notificationCoordinator = NotificationCoordinator(
            service: NotificationService(),
            idsRepo: ScheduledNotificationIdsRepo(),
            inventory: self.inventoryRepository,
            reminderSettings: self.reminderSettingsStore
        )
        let clientProvider = SupabaseClientProvider(config: config)
        self.clientProvider = clientProvider
        self.authService = AuthService(backend: clientProvider.authBackend)

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
            let gateway = SupabaseSyncGateway(client: client)
            let coordinator = SyncCoordinator(outbox: outbox, remote: gateway)
            self.syncCoordinator = coordinator
            let remoteRepository = RemotePantryRepository(
                client: client,
                apiBaseURL: (config?.backend.apiBaseURL ?? BackendConfig.defaultAPIBaseURL).absoluteString
            )
            self.remotePantryRepository = remoteRepository
            self.syncWriter = SyncWriter(outbox: outbox, coordinator: coordinator, session: session)
            self.householdContentSync = HouseholdContentSyncCoordinator(
                remote: remoteRepository,
                push: coordinator,
                outbox: outbox,
                inventory: self.inventoryRepository,
                shopping: self.shoppingRepository,
                customRecipe: self.customRecipeRepository,
                mealPlan: self.mealPlanRepository,
                session: session
            )
        } else {
            self.syncCoordinator = nil
            self.remotePantryRepository = nil
            self.syncWriter = SyncWriter(outbox: outbox, coordinator: nil, session: session)
            self.householdContentSync = nil
        }
    }
}
