import Foundation
import Testing
@testable import FreshPantry

/// Tests for the session/sync state-machine edges added by the closed-loop
/// pass: the status banner's failed-vs-syncing copy, the invite deep-link
/// presentation gate (including the cold-start hold while the Keychain session
/// restore is unresolved), and the inbound-sync retry gate.
struct SyncStateGateTests {
    // MARK: - SyncStatusBanner.message

    @Test func offlineMessageKeepsPlainQueueDepth() {
        // Offline ops aren't failures — the failed count must not leak in.
        #expect(SyncStatusBanner.message(isOnline: false, pendingCount: 3, failedCount: 2)
            == String(localized: "sync.banner.offlinePending \(3)"))
        #expect(SyncStatusBanner.message(isOnline: false, pendingCount: 0, failedCount: 0)
            == String(localized: "sync.banner.offline"))
    }

    @Test func onlineWithoutFailuresSaysSyncing() {
        #expect(SyncStatusBanner.message(isOnline: true, pendingCount: 2, failedCount: 0)
            == String(localized: "sync.banner.syncing \(2)"))
    }

    @Test func onlineFailedOnlyDropsTheEternalSyncing() {
        // The whole queue is dead-lettered: no 「同步中」 lie.
        #expect(SyncStatusBanner.message(isOnline: true, pendingCount: 2, failedCount: 2)
            == String(localized: "sync.banner.failed \(2)"))
    }

    @Test func onlineFailedPlusLiveSplitsTheCounts() {
        #expect(SyncStatusBanner.message(isOnline: true, pendingCount: 5, failedCount: 2)
            == String(localized: "sync.banner.failedPending \(2) \(3)"))
    }

    @Test func failedCountAboveQueueDepthClampsAtZeroSyncing() {
        // A stale failed count (queue shrank between refreshes) must not render
        // a negative remainder.
        #expect(SyncStatusBanner.message(isOnline: true, pendingCount: 1, failedCount: 3)
            == String(localized: "sync.banner.failed \(3)"))
    }

    @Test func droppedWriteWinsOverEveryOtherState() {
        // A dropped local write is a LOCAL storage failure — it outranks offline,
        // pending, and dead-letter, and shows regardless of connectivity.
        #expect(SyncStatusBanner.message(isOnline: false, pendingCount: 5, failedCount: 2, droppedCount: 1)
            == String(localized: "sync.banner.dropped \(1)"))
        #expect(SyncStatusBanner.message(isOnline: true, pendingCount: 0, failedCount: 0, droppedCount: 3)
            == String(localized: "sync.banner.dropped \(3)"))
    }

    // MARK: - InviteRouter.gateOutcome

    @Test func noPendingInviteIsNoAction() {
        #expect(InviteRouter.gateOutcome(hasPendingInvite: false, sessionResolved: true, isLocalOnly: false, isSignedIn: true)
            == .none)
        #expect(InviteRouter.gateOutcome(hasPendingInvite: false, sessionResolved: true, isLocalOnly: true, isSignedIn: false)
            == .none)
    }

    @Test func signedInPresentsPreview() {
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: true, isLocalOnly: false, isSignedIn: true)
            == .presentPreview)
    }

    @Test func signedOutPromptsSignInKeepingToken() {
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: true, isLocalOnly: false, isSignedIn: false)
            == .promptSignIn)
    }

    @Test func localOnlyIsUnsupportedRegardlessOfSignIn() {
        // Local-only wins: there is no login to send the user to.
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: true, isLocalOnly: true, isSignedIn: false)
            == .unsupported)
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: true, isLocalOnly: true, isSignedIn: true)
            == .unsupported)
    }

    @Test func unresolvedSessionHoldsTheGate() {
        // Cold-start race: the Keychain restore hasn't settled, so a signed-out
        // read isn't trustworthy yet — hold (token kept, no alert) instead of
        // flashing a wrong 「请先登录」 at an already-signed-in user.
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: false, isLocalOnly: false, isSignedIn: false)
            == .none)
        // Holding also when a signed-in read races ahead is safe: the gate only
        // emits alerts; the preview sheet binding presents independently.
        #expect(InviteRouter.gateOutcome(hasPendingInvite: true, sessionResolved: false, isLocalOnly: false, isSignedIn: true)
            == .none)
    }

    // MARK: - AuthService.hasResolvedSession

    /// Minimal `AuthBackend` for the session-resolution flag — only the restore
    /// path matters here (the full state machine is covered in AuthServiceTests).
    private final class RestoreOnlyBackend: AuthBackend, @unchecked Sendable {
        let restoreEmail: String?
        init(restoreEmail: String?) { self.restoreEmail = restoreEmail }
        func restoreSessionEmail() async -> String? { restoreEmail }
        func sendCode(email: String) async throws {}
        func verify(email: String, code: String) async throws -> String { email }
        func signOut() async {}
    }

    @Test @MainActor func localOnlyResolvesSessionAtBirth() {
        // No backend → nothing to restore; the invite gate must not wait forever.
        #expect(AuthService(backend: nil).hasResolvedSession)
    }

    @Test @MainActor func configuredBackendResolvesOnlyAfterRestore() async {
        let service = AuthService(backend: RestoreOnlyBackend(restoreEmail: "a@b.com"))
        #expect(!service.hasResolvedSession)
        await service.restore()
        #expect(service.hasResolvedSession)
        #expect(service.signedInEmail == "a@b.com")
    }

    @Test @MainActor func restoreWithoutPersistedSessionStillResolves() async {
        // "Resolved" means the session question is ANSWERED, not "signed in" —
        // a confirmed signed-out must also unblock the gate (→ .promptSignIn).
        let service = AuthService(backend: RestoreOnlyBackend(restoreEmail: nil))
        await service.restore()
        #expect(service.hasResolvedSession)
        #expect(service.signedInEmail == nil)
    }

    // MARK: - HouseholdContentSyncCoordinator.shouldRetry

    @Test func retryRequiresAFailedRunAndAnActiveHousehold() {
        #expect(HouseholdContentSyncCoordinator.shouldRetry(needsRetry: true, activeHouseholdId: "home"))
    }

    @Test func successfulLastRunNeverRetries() {
        #expect(!HouseholdContentSyncCoordinator.shouldRetry(needsRetry: false, activeHouseholdId: "home"))
    }

    @Test func localOnlyScopeNeverRetries() {
        // Stop/sign-out cleared the scope — a queued retry mark must die with it.
        #expect(!HouseholdContentSyncCoordinator.shouldRetry(needsRetry: true, activeHouseholdId: ""))
    }
}
