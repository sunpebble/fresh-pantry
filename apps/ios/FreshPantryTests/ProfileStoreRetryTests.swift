import Foundation
import Testing
@testable import FreshPantry

/// Tests for the explicit-retry loop on `ProfileStore`: a failed save must be
/// recoverable from the 重试 affordance (success flushes pending + clears the
/// error; failure stays pending AND surfaces feedback — never silent).
@MainActor
struct ProfileStoreRetryTests {
    /// Remote fake whose upsert failure is switchable mid-test, so the
    /// fail-then-recover round trip can be exercised.
    final class FlakyProfileRemote: ProfileRemote, @unchecked Sendable {
        var stored: UserProfile?
        var failUpsert = false
        var upsertCount = 0

        func loadMyProfile() async throws -> UserProfile? { stored }
        func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws {
            upsertCount += 1
            if failUpsert { throw RemotePantryError.notSignedIn(action: "test") }
            stored = UserProfile(id: "me", email: "me@x.com", displayName: displayName, nickname: nickname, avatarPath: avatarPath)
        }
        func uploadAvatar(_ data: Data) async throws -> String { "me/new.jpg" }
        nonisolated func avatarPublicURL(path: String) -> URL? { nil }
    }

    private func makeStore(remote: FlakyProfileRemote) throws -> ProfileStore {
        let container = try ModelContainerFactory.makeInMemory()
        return ProfileStore(remote: remote, local: ProfileRepository(modelContainer: container))
    }

    /// Seeds a pending edit by saving while the remote rejects the upsert.
    private func makePendingStore(remote: FlakyProfileRemote) async throws -> ProfileStore {
        remote.failUpsert = true
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: nil)
        #expect(store.hasPendingUpload)
        return store
    }

    @Test func manualRetryFlushesPendingAndClearsError() async throws {
        let remote = FlakyProfileRemote()
        let store = try await makePendingStore(remote: remote)

        remote.failUpsert = false
        await store.retryPendingUpload()

        #expect(!store.hasPendingUpload)
        #expect(store.errorMessage == nil)
        #expect(!store.isRetrying)
        #expect(remote.stored?.displayName == "阿花")
    }

    @Test func failedRetryStaysPendingAndSurfacesError() async throws {
        let remote = FlakyProfileRemote()
        let store = try await makePendingStore(remote: remote)

        await store.retryPendingUpload() // remote still failing

        #expect(store.hasPendingUpload)
        #expect(store.errorMessage != nil)
        #expect(!store.isRetrying)
    }

    @Test func retryIsNoOpWithoutPendingEdit() async throws {
        let remote = FlakyProfileRemote()
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        let baseline = remote.upsertCount

        await store.retryPendingUpload()

        #expect(remote.upsertCount == baseline)
        #expect(store.errorMessage == nil)
    }

    /// The save-failure message must not promise an automatic retry — the only
    /// triggers are the explicit 重试 button and the next load.
    @Test func failedSaveMessageDoesNotPromiseAutoRetry() async throws {
        let remote = FlakyProfileRemote()
        let store = try await makePendingStore(remote: remote)
        let message = try #require(store.errorMessage)
        #expect(!message.contains("自动重试"))
    }
}
