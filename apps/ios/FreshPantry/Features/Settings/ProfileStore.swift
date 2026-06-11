import Foundation

/// Drives the profile-edit + onboarding UI. Local-first optimistic writes: an
/// edit updates local state immediately, then pushes to the backend; a push
/// failure RETAINS a pending flag and surfaces the error (never silent). Single
/// writer (only "me"), so there is no version/merge — just last-write + retry.
@Observable
@MainActor
final class ProfileStore {
    private(set) var displayName = ""
    private(set) var nickname = ""
    private(set) var avatarPath = ""
    private(set) var email = ""
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var hasPendingUpload = false
    private(set) var hasLoaded = false

    private let remote: ProfileRemote?
    private let local: ProfileRepository
    /// Whether the user is signed in — gates `needsProfileSetup` (a signed-out /
    /// local-only user is never asked to fill a profile). Set by `load`.
    private var isSignedIn = false

    init(remote: ProfileRemote?, local: ProfileRepository) {
        self.remote = remote
        self.local = local
    }

    /// True when we should force the onboarding profile step: loaded, signed in,
    /// and no display name yet.
    var needsProfileSetup: Bool {
        hasLoaded && isSignedIn && displayName.trimmed.isEmpty
    }

    /// Public URL of the current avatar (nil when none / no backend).
    var avatarURL: URL? { remote?.avatarPublicURL(path: avatarPath) }

    /// Loads local cache first (instant), then refreshes from the backend. A
    /// remote failure keeps the local snapshot (offline-tolerant).
    func load(signedIn: Bool) async {
        isSignedIn = signedIn
        if let cached = try? await local.load() {
            apply(cached.profile)
            hasPendingUpload = cached.pendingUpload
        }
        if signedIn, let remote {
            do {
                if let fetched = try await remote.loadMyProfile() {
                    apply(fetched)
                    try? await local.save(fetched, pendingUpload: false)
                    hasPendingUpload = false
                }
            } catch {
                // Keep the local snapshot; surfacing here would be noisy on launch.
            }
        }
        hasLoaded = true
        // A still-pending edit from a previous session: try to flush it now.
        if hasPendingUpload { await retryPendingUpload() }
    }

    /// Optimistic save. Uploads a new avatar first (if any), then upserts the row.
    /// On success clears pending; on failure retains pending + sets errorMessage.
    func save(displayName newName: String, nickname newNick: String, newAvatar: Data?) async {
        isSaving = true
        errorMessage = nil
        let trimmedName = newName.trimmed
        let trimmedNick = newNick.trimmed

        // Optimistic local state immediately.
        displayName = trimmedName
        nickname = trimmedNick

        do {
            var path = avatarPath
            if let data = newAvatar, let remote {
                path = try await remote.uploadAvatar(data)
            }
            avatarPath = path
            let profile = UserProfile(id: "", email: email, displayName: trimmedName, nickname: trimmedNick, avatarPath: path)

            guard let remote else {
                // No backend (local-only): persist locally, mark pending so it
                // flushes once a backend/household is wired.
                try? await local.save(profile, pendingUpload: true)
                hasPendingUpload = true
                isSaving = false
                return
            }

            try await remote.upsertMyProfile(displayName: trimmedName, nickname: trimmedNick, avatarPath: path)
            try? await local.save(profile, pendingUpload: false)
            hasPendingUpload = false
        } catch {
            // Retain the edit + pending flag so the foreground/online retry resends.
            let profile = UserProfile(id: "", email: email, displayName: trimmedName, nickname: trimmedNick, avatarPath: avatarPath)
            try? await local.save(profile, pendingUpload: true)
            hasPendingUpload = true
            errorMessage = "保存失败，已在本地保留，稍后会自动重试。"
        }
        isSaving = false
    }

    /// Re-pushes a pending local edit. Called on load and can be called on
    /// foreground / reconnect. No-op when nothing is pending or no backend.
    func retryPendingUpload() async {
        guard hasPendingUpload, let remote else { return }
        do {
            try await remote.upsertMyProfile(displayName: displayName, nickname: nickname, avatarPath: avatarPath)
            let profile = UserProfile(id: "", email: email, displayName: displayName, nickname: nickname, avatarPath: avatarPath)
            try? await local.save(profile, pendingUpload: false)
            hasPendingUpload = false
            errorMessage = nil
        } catch {
            // Still pending; leave the flag set for the next trigger.
        }
    }

    private func apply(_ profile: UserProfile) {
        displayName = profile.displayName
        nickname = profile.nickname
        avatarPath = profile.avatarPath
        if !profile.email.isEmpty { email = profile.email }
    }
}
