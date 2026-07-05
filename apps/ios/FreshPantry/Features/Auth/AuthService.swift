import Foundation

/// The email-OTP auth state machine — the single source of truth for the
/// account UI's session state.
///
/// `@Observable @MainActor` so SwiftUI views bind directly. All Supabase calls
/// go through the injected `AuthBackend` seam (nil = no backend configured →
/// permanent `.localOnly`), so the state-machine logic here is fully testable
/// with a fake backend and never imports the SDK.
///
/// State flow (mirrors the Flutter two-stage login):
/// `.signedOut` → sendCode → `.codeSent(email)` → verify → `.signedIn(email)`;
/// a verify failure stays in `.codeSent` (so the user can retry the code without
/// re-requesting). `.localOnly` is terminal when no backend is configured.
@Observable
@MainActor
final class AuthService {
    /// The authentication state surfaced to the UI.
    enum State: Equatable {
        /// No backend configured (empty `Secrets.plist`) — sign-in is disabled
        /// and the app runs purely local. Never transitions.
        case localOnly
        /// Backend present, no session — the login form shows the email entry.
        case signedOut
        /// A 6-digit code was emailed; the UI shows the code-entry step.
        case codeSent(email: String)
        /// Authenticated — the UI shows the signed-in account row.
        case signedIn(userEmail: String)
    }

    private(set) var state: State
    /// True once the launch-time session question is answered — `restore()`
    /// completed (signed in OR confirmed signed out), or no backend exists so
    /// there is nothing to restore. Before this flips, `.signedOut` may just
    /// mean "Keychain restore still in flight" — the invite deep-link gate
    /// keys on this so a cold-start link waits instead of misreading the
    /// pre-restore state as 「未登录」.
    private(set) var hasResolvedSession: Bool
    /// In-flight flag for the active async op (drives button spinners/disabling).
    private(set) var isBusy = false
    /// The last user-facing error, cleared at the start of each new attempt.
    private(set) var errorMessage: String?
    /// Wall-clock time when another OTP request is allowed.
    private(set) var resendAvailableAt: Date?

    // Keep in sync with supabase/config.toml [auth.email].max_frequency.
    private static let resendCooldown: TimeInterval = 60
    private let backend: AuthBackend?
    private let now: () -> Date

    /// Injects the backend seam. Pass `nil` for local-only mode (no config).
    /// Session restore runs in `restore()` (call it once after construction in a
    /// `.task`) so init stays synchronous and the initial state is deterministic.
    init(backend: AuthBackend?, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.now = now
        self.state = backend == nil ? .localOnly : .signedOut
        // Local-only has no persisted session to restore — resolved at birth.
        self.hasResolvedSession = backend == nil
    }

    /// True when a backend is configured (sign-in is possible).
    var isConfigured: Bool { backend != nil }

    /// The signed-in user's email, or nil when not signed in.
    var signedInEmail: String? {
        if case let .signedIn(email) = state { return email }
        return nil
    }

    func resendCooldownRemaining(at date: Date) -> Int {
        guard let resendAvailableAt else { return 0 }
        return max(0, Int(ceil(resendAvailableAt.timeIntervalSince(date))))
    }

    // MARK: Session restore

    /// Rehydrates a persisted session on launch. No-op in local-only mode. Idempotent.
    /// Flips `hasResolvedSession` on EVERY exit path — a signed-out answer also
    /// resolves the session question (it unblocks the invite gate's 「请先登录」).
    func restore() async {
        defer { hasResolvedSession = true }
        guard let backend, case .signedOut = state else { return }
        if let email = await backend.restoreSessionEmail() {
            state = .signedIn(userEmail: email)
        }
    }

    // MARK: Send code

    /// Sends a 6-digit OTP to `email`. On success moves to `.codeSent`.
    func sendCode(email: String) async {
        guard let backend else { return }
        let trimmed = email.trimmed
        guard isValidEmail(trimmed) else {
            errorMessage = String(localized: "auth.error.invalidEmail")
            return
        }
        await run {
            try await backend.sendCode(email: trimmed)
            self.resendAvailableAt = self.now().addingTimeInterval(Self.resendCooldown)
            self.state = .codeSent(email: trimmed)
        }
    }

    // MARK: Verify

    /// Verifies the 6-digit `code` for the email captured in `.codeSent`. On
    /// success moves to `.signedIn`; on failure stays in `.codeSent` with an error.
    func verify(code: String) async {
        guard let backend, case let .codeSent(email) = state else { return }
        let trimmed = code.trimmed
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "auth.error.emptyCode")
            return
        }
        await run {
            let userEmail = try await backend.verify(email: email, code: trimmed)
            self.resendAvailableAt = nil
            self.state = .signedIn(userEmail: userEmail)
        }
    }

    #if DEBUG
    /// Automation-only: verify an OTP for an EXPLICIT email. The normal `verify`
    /// reads the email from the in-memory `.codeSent` state, which a fresh launch
    /// (after the code was requested in a prior launch) doesn't have — but the
    /// server-side OTP is valid regardless of which client session requested it,
    /// so this seeds `.codeSent(email)` then runs the normal verify. Drives the
    /// `-debugAuthVerify` launch hook used for automated live-sync verification.
    func debugVerify(email: String, code: String) async {
        guard backend != nil else { return }
        state = .codeSent(email: email)
        await verify(code: code)
    }
    #endif

    // MARK: Sign out

    /// Signs out and returns to `.signedOut`. No-op in local-only mode.
    func signOut() async {
        guard let backend else { return }
        isBusy = true
        errorMessage = nil
        await backend.signOut()
        resendAvailableAt = nil
        state = .signedOut
        isBusy = false
    }

    // MARK: Helpers

    /// Wraps an async op with busy/error bookkeeping; maps thrown errors to a
    /// user-facing message and leaves state unchanged on failure.
    private func run(_ op: @MainActor () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await op()
        } catch let failure as AuthFailure {
            errorMessage = failure.message
        } catch {
            errorMessage = AuthFailure.generic.message
        }
        isBusy = false
    }

    /// Minimal email shape check mirroring the Flutter regex
    /// `^[^@\s]+@[^@\s]+\.[^@\s]+$`.
    private func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}
