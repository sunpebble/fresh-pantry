import BackgroundTasks
import SwiftData
import SwiftUI

/// Application entry point.
///
/// Fresh Pantry is a local-first household pantry app, rewritten natively in
/// SwiftUI for iOS and iPadOS. State is persisted with SwiftData and synced to
/// Supabase for family sharing (both layered in over the course of the
/// migration — see `docs/swiftui-migration/PLAN.md`).
///
/// Wiring pattern (reused by every feature): one shared `ModelContainer` is
/// built here, injected via `.modelContainer`, and used to construct the
/// `AppDependencies` repositories injected via `.environment`. Feature stores
/// read `AppDependencies` to build themselves.
@main
struct FreshPantryApp: App {
    /// BGTaskScheduler identifier for the periodic background outbox flush.
    /// MUST match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    private static let backgroundSyncTaskId = "fresh_pantry.periodic_sync"

    private let modelContainer: ModelContainer
    @State private var dependencies: AppDependencies
    /// The app-root-resident sync session — the SINGLE instance every store
    /// enqueues against. Injected into both `AppDependencies` and the environment
    /// so the household-management UI binds to THIS instance (a per-screen
    /// session would silently no-op every enqueue — see `SyncSession` invariant).
    @State private var syncSession: SyncSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Unit tests host inside this app target (xcodegen sets TEST_HOST), so the
        // app boots during `xcodebuild test`. Use an in-memory store under XCTest:
        // keeps the app host from writing an on-disk `default.store` into the
        // simulator (the harmless but noisy CoreData "Failed to stat …default.store"
        // log) and keeps runs isolated — tests build their own containers anyway.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let container = isRunningTests
            ? (try! ModelContainerFactory.makeInMemory())
            : ((try? ModelContainerFactory.makeShared()) ?? (try! ModelContainerFactory.makeInMemory()))
        self.modelContainer = container
        // Load backend config; an empty/absent Secrets.plist (the default for
        // local dev / OSS checkouts) yields nil → the app runs in local-only
        // mode (auth disabled) rather than crashing.
        let config = try? AppConfig.load()
        // Start crash/error reporting before anything else can fail. No-op in
        // DEBUG and when config is absent (local-only) — see SentryBootstrap.
        SentryBootstrap.start(config?.sentry)
        let session = SyncSession()
        _syncSession = State(initialValue: session)
        _dependencies = State(
            initialValue: AppDependencies(
                modelContainer: container,
                config: config,
                syncSession: session
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.fkPrimary)
                // 外观偏好:跟随系统时为 nil(交还系统);浅色/深色为硬覆盖。
                // App/Scene body 会追踪 @Observable 读取,设置页切换即时生效。
                .preferredColorScheme(dependencies.appearanceStore.mode.colorScheme)
                .modelContainer(modelContainer)
                .environment(dependencies)
                .environment(syncSession)
                .environment(dependencies.inviteRouter)
                .environment(dependencies.recipeImportRouter)
                .onOpenURL { url in
                    // Share-extension recipe import → capture + short-circuit
                    // (RecipesView opens the pre-filled 新建食谱). Then invite deep
                    // link → capture (RootView presents preview/accept). Otherwise
                    // fall through to the SDK auth handler (OTP link flows). Each
                    // `capture` is a no-op for URLs it doesn't own.
                    if dependencies.recipeImportRouter.capture(url: url) { return }
                    if dependencies.inviteRouter.capture(url: url) { return }
                    dependencies.clientProvider.handleOpenURL(url)
                }
                // Submit the first background-refresh request once on launch so
                // iOS can schedule an opportunistic flush even before the first
                // background transition.
                .task { Self.scheduleAppRefresh() }
                // Re-arm the background request when leaving the foreground (each
                // BGTask is one-shot — it must resubmit itself, see below).
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Self.scheduleAppRefresh() }
                }
            // DEBUG sample seeding is done by each feature view's own `.task`
            // (seed-then-load), so data is guaranteed present before the view
            // loads it — avoids a race between an app-level seeder and the
            // feature store's load().
        }
        // BACKGROUND OUTBOX FLUSH: iOS runs this opportunistically (throttled);
        // the dependable flush stays the ScenePhase .active foreground path in
        // RootView. Each run drains the outbox then resubmits the next request,
        // since a BGTask fires once. nil syncCoordinator (local-only) is a no-op.
        .backgroundTask(.appRefresh(Self.backgroundSyncTaskId)) {
            await dependencies.syncCoordinator?.pushPending()
            await MainActor.run { Self.scheduleAppRefresh() }
        }
    }

    /// Submits a periodic background-refresh request (earliest in 15 min).
    /// Wrapped in `try?`: submission fails on the simulator and when the app is
    /// unentitled, which is expected and harmless. Must be called on the main
    /// actor (the `@MainActor` annotation keeps the BGTaskScheduler call there).
    @MainActor
    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundSyncTaskId)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
