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
        let container = (try? ModelContainerFactory.makeShared())
            ?? (try! ModelContainerFactory.makeInMemory())
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
                .preferredColorScheme(.light) // 品牌为暖色浅色主题;深色模式留作后续增强
                .modelContainer(modelContainer)
                .environment(dependencies)
                .environment(syncSession)
                .onOpenURL { url in
                    // Auth callback scheme. The OTP code flow is verified in-app,
                    // so this is a minimal pass-through for any link-based flow
                    // (e.g. invites in the next slice). Hand any session-bearing
                    // URL to the SDK; non-auth links are ignored downstream.
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
