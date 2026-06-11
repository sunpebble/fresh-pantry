import Foundation
import Testing
@testable import FreshPantry

@MainActor
struct ProfileStoreTests {
    /// In-memory fake of the remote seam. `failUpsert` forces the push to throw so
    /// the pending-retention path can be asserted.
    final class FakeProfileRemote: ProfileRemote, @unchecked Sendable {
        var stored: UserProfile?
        var uploadedCount = 0
        var failUpsert = false

        func loadMyProfile() async throws -> UserProfile? { stored }
        func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws {
            if failUpsert { throw RemotePantryError.notSignedIn(action: "test") }
            stored = UserProfile(id: "me", email: "me@x.com", displayName: displayName, nickname: nickname, avatarPath: avatarPath)
        }
        func uploadAvatar(_ data: Data) async throws -> String { uploadedCount += 1; return "me/new.jpg" }
        nonisolated func avatarPublicURL(path: String) -> URL? {
            path.isEmpty ? nil : URL(string: "https://cdn/\(path)")
        }
    }

    private func makeStore(remote: FakeProfileRemote?) throws -> ProfileStore {
        let container = try ModelContainerFactory.makeInMemory()
        return ProfileStore(remote: remote, local: ProfileRepository(modelContainer: container))
    }

    @Test func loadPullsRemoteIntoState() async throws {
        let remote = FakeProfileRemote()
        remote.stored = UserProfile(id: "me", email: "me@x.com", displayName: "小明", nickname: "明")
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        #expect(store.displayName == "小明")
        #expect(store.nickname == "明")
        #expect(store.hasLoaded)
    }

    @Test func needsProfileSetupWhenSignedInAndNoDisplayName() async throws {
        let store = try makeStore(remote: FakeProfileRemote())   // remote.stored == nil
        await store.load(signedIn: true)
        #expect(store.needsProfileSetup)
    }

    @Test func savedDisplayNameClearsNeedsSetup() async throws {
        let remote = FakeProfileRemote()
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: nil)
        #expect(!store.needsProfileSetup)
        #expect(store.errorMessage == nil)
        #expect(!store.hasPendingUpload)
        #expect(remote.stored?.displayName == "阿花")
    }

    @Test func failedSaveRetainsPendingAndSurfacesError() async throws {
        let remote = FakeProfileRemote()
        remote.failUpsert = true
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: nil)
        #expect(store.hasPendingUpload)
        #expect(store.errorMessage != nil)
        #expect(store.displayName == "阿花")
    }

    @Test func uploadsAvatarBeforeUpsert() async throws {
        let remote = FakeProfileRemote()
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: Data([0xFF]))
        #expect(remote.uploadedCount == 1)
        #expect(store.avatarPath == "me/new.jpg")
    }
}
