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
    /// In-flight flag for an explicit 重试 — drives the retry button's spinner.
    private(set) var isRetrying = false
    private(set) var errorMessage: String?
    /// Raw description of the last push failure's underlying error, for diagnosis
    /// (the friendly `errorMessage` is what the user reads). Cleared on success.
    private(set) var lastFailureDetail: String?
    private(set) var hasPendingUpload = false
    private(set) var hasLoaded = false

    private let remote: ProfileRemote?
    private let local: ProfileRepository
    /// Whether the user is signed in — gates `needsProfileSetup` (a signed-out /
    /// local-only user is never asked to fill a profile). Set by `load`.
    private var isSignedIn = false
    /// Bytes of an avatar the user picked that haven't landed in Storage yet. Held
    /// so an explicit 重试 RE-UPLOADS it (not just re-pushes the row) — a failed
    /// avatar upload otherwise leaves the row pointing at the old path with the
    /// picked bytes lost, so the avatar could never recover. In-memory only: after
    /// a relaunch this is nil and a retry degrades to re-pushing the row with the
    /// already-persisted `avatarPath` (the user re-picks to retry the image).
    private var pendingAvatarData: Data?

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

    /// Optimistic save. Records the picked avatar bytes, updates local state, then
    /// flushes (upload avatar + upsert row). On success clears pending; on failure
    /// retains pending — including the avatar bytes — and sets errorMessage.
    func save(displayName newName: String, nickname newNick: String, newAvatar: Data?) async {
        isSaving = true
        errorMessage = nil

        // Optimistic local state immediately.
        displayName = newName.trimmed
        nickname = newNick.trimmed
        if let newAvatar { pendingAvatarData = newAvatar }

        if await flushPendingProfile() != nil {
            errorMessage = "保存失败，修改已保留在本机，可手动重试。"
        }
        isSaving = false
    }

    /// Re-flushes a pending local edit. Called on load and by the explicit 重试
    /// affordance in the profile views. No-op when nothing is pending, no
    /// backend, or a retry is already in flight. A failure keeps the pending
    /// flag AND surfaces errorMessage, so a tapped 重试 never fails silently.
    func retryPendingUpload() async {
        guard hasPendingUpload, !isRetrying, remote != nil else { return }
        isRetrying = true
        errorMessage = nil
        defer { isRetrying = false }
        if await flushPendingProfile() != nil {
            // Trigger-neutral wording: the same message shows for the load-time flush.
            errorMessage = "同步未完成，修改仍保留在本机，请检查网络后重试。"
        }
    }

    /// Uploads a still-pending avatar (if any) then upserts the row — the single
    /// push path shared by `save` and `retryPendingUpload`. Returns nil on success
    /// (clears pending + the held bytes); returns the error on failure, retaining
    /// the pending flag AND `pendingAvatarData` so a later retry resends BOTH the
    /// avatar and the row (the original bug: retry re-pushed only the empty path).
    private func flushPendingProfile() async -> Error? {
        do {
            var path = avatarPath
            if let data = pendingAvatarData, let remote {
                path = try await remote.uploadAvatar(data)
            }
            avatarPath = path
            let profile = UserProfile(id: "", email: email, displayName: displayName, nickname: nickname, avatarPath: path)

            guard let remote else {
                // No backend (local-only): persist locally, mark pending so it
                // flushes once a backend/household is wired.
                try? await local.save(profile, pendingUpload: true)
                hasPendingUpload = true
                return nil
            }

            try await remote.upsertMyProfile(displayName: displayName, nickname: nickname, avatarPath: path)
            try? await local.save(profile, pendingUpload: false)
            hasPendingUpload = false
            pendingAvatarData = nil
            lastFailureDetail = nil
            return nil
        } catch {
            // Retain the edit + pending flag + avatar bytes so the next trigger
            // (explicit 重试 / next load) resends. avatarPath keeps its prior value
            // when the upload itself failed. Capture the raw error so the real
            // cause (e.g. a storage RLS rejection) is no longer hidden behind the
            // generic message — the bug that made this defect un-diagnosable.
            let profile = UserProfile(id: "", email: email, displayName: displayName, nickname: nickname, avatarPath: avatarPath)
            try? await local.save(profile, pendingUpload: true)
            hasPendingUpload = true
            lastFailureDetail = String(describing: error)
            return error
        }
    }

    private func apply(_ profile: UserProfile) {
        displayName = profile.displayName
        nickname = profile.nickname
        avatarPath = profile.avatarPath
        if !profile.email.isEmpty { email = profile.email }
    }
}
