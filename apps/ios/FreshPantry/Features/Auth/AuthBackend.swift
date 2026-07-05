import Foundation

/// SDK-agnostic seam over the auth provider's email-OTP flow.
///
/// `AuthService` talks only to this protocol; the production impl
/// (`SupabaseAuthBackend`) wraps `SupabaseClient.auth`, and tests inject a fake.
/// This is the boundary the next sync slice plugs into — the household-data
/// engine will reach the same `SupabaseClient` via `SupabaseClientProvider`,
/// while auth concerns stay isolated here.
///
/// Keeping the Supabase SDK import OUT of `AuthService` (it lives only in the
/// concrete backend) means the state-machine logic is unit-testable without the
/// SDK, the simulator, or live credentials.
protocol AuthBackend: Sendable {
    /// The currently restored user email if a persisted session exists, else nil.
    /// Called on `AuthService` init for session restore (the SDK rehydrates the
    /// session from its Keychain storage synchronously at construction).
    func restoreSessionEmail() async -> String?

    /// Requests a 6-digit OTP code be emailed to `email` (creating the user if
    /// new). Mirrors Flutter `signInWithOtp(email:, emailRedirectTo:)`.
    func sendCode(email: String) async throws

    /// Verifies the 6-digit `code` for `email`; returns the authenticated user's
    /// email on success. Mirrors Flutter `verifyEmailOtp` with the dual-type
    /// fallback (`.email` then `.signup`) so brand-new signups also succeed.
    func verify(email: String, code: String) async throws -> String

    /// Clears the persisted session locally and remotely.
    func signOut() async
}

/// A user-facing auth failure carrying a localized (Chinese) message.
///
/// `AuthService` maps lower-level errors (SDK `AuthError`, transport failures)
/// into this so the UI never surfaces a raw English SDK string.
struct AuthFailure: Error, Equatable {
    let message: String

    /// The generic fallback when no more specific message is available.
    static let generic = AuthFailure(message: String(localized: "auth.error.generic"))
}
