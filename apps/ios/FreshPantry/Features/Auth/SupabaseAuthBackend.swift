import Foundation
import Supabase

/// The production `AuthBackend` — wraps `SupabaseClient.auth`.
///
/// This is the ONLY auth file that imports the Supabase SDK. It translates the
/// SDK's email-OTP API into the `AuthBackend` seam and maps `AuthError` into the
/// localized `AuthFailure` that the UI shows.
///
/// PARITY-CRITICAL: `verify` tries `EmailOTPType.email` first and, on failure,
/// retries with `.signup`. Existing users get email-type magic-link codes;
/// brand-new signups get signup-type confirmation codes. A wrong-type attempt
/// errors WITHOUT consuming a valid token, so the fallback is safe and REQUIRED
/// or first-time login breaks (mirrors the Flutter `verifyEmailOtp`).
struct SupabaseAuthBackend: AuthBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func restoreSessionEmail() async -> String? {
        // Use the ASYNC `auth.session` getter, which loads (and refreshes) the
        // persisted session from the Keychain. The synchronous `currentSession` /
        // `currentUser` are nil immediately after launch — before the SDK's async
        // rehydrate completes — so reading them would drop a still-valid login and
        // leave a returning member signed out (no sync until they re-open login).
        guard let session = try? await client.auth.session else { return nil }
        return session.user.email
    }

    func sendCode(email: String) async throws {
        do {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: SupabaseClientProvider.authRedirectURL,
                shouldCreateUser: true
            )
        } catch {
            throw mapError(error)
        }
    }

    func verify(email: String, code: String) async throws -> String {
        // Try existing-user (.email) type first; fall back to new-signup (.signup).
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            return response.user.email ?? email
        } catch {
            do {
                let response = try await client.auth.verifyOTP(email: email, token: code, type: .signup)
                return response.user.email ?? email
            } catch {
                throw mapError(error)
            }
        }
    }

    func signOut() async {
        // signOut throws only on a network failure clearing the remote session;
        // the local session is always cleared, so swallow — the UI returns to
        // signedOut regardless.
        try? await client.auth.signOut()
    }

    /// Maps SDK / transport errors into a localized `AuthFailure`.
    private func mapError(_ error: Error) -> AuthFailure {
        if let authError = error as? AuthError {
            return AuthFailure(message: localizedMessage(for: authError))
        }
        if (error as? URLError) != nil {
            return AuthFailure(message: String(localized: "auth.error.network"))
        }
        return .generic
    }

    /// Chinese copy for the auth errors a user can realistically hit. Falls back
    /// to the SDK message for anything unmapped so failures stay visible.
    /// `ErrorCode` is a string-wrapper struct (not an enum), so compare by value.
    private func localizedMessage(for error: AuthError) -> String {
        let code = error.errorCode
        if code == .otpExpired {
            return String(localized: "auth.error.otpExpired")
        }
        if code == .overRequestRateLimit || code == .overEmailSendRateLimit {
            return String(localized: "auth.error.rateLimit")
        }
        if code == .validationFailed {
            return String(localized: "auth.error.invalidOtp")
        }
        return error.message
    }
}
