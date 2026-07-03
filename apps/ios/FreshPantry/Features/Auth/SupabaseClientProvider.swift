import Foundation
import Supabase

/// Builds and owns the single `SupabaseClient` for the app.
///
/// The client is the shared entry point for BOTH auth (this slice) and the
/// household-data sync engine (the next slice), so it lives in one provider that
/// both layers read. It is `nil` when no backend is configured (empty
/// `Secrets.plist`), which puts the app in local-only mode.
///
/// Auth config:
/// - Session storage is the SDK's `KeychainLocalStorage`, so the session (and
///   its refresh token) survives launches in the Keychain and the SDK manages
///   auto-refresh — we do NOT hand-roll session persistence.
/// - `redirectToURL` is the registered custom scheme. Per the project's
///   email-OTP decision the app verifies a 6-digit code in-app (`verifyOTP`),
///   so the deep-link round-trip is vestigial for the code flow; the redirect is
///   still configured for any link-based flow (e.g. invites) the SDK may emit.
struct SupabaseClientProvider {
    /// The custom-scheme auth callback, matching the Flutter
    /// `supabaseAuthRedirectUrl` and the Supabase project `site_url`.
    static let authRedirectURL = URL(string: "com.sunpebble.freshpantry://signin-callback/")!

    /// The shared client, or nil when no backend is configured.
    let client: SupabaseClient?

    /// Builds the client from resolved `AppConfig`. Pass `nil` for local-only.
    init(config: AppConfig?) {
        guard let config else {
            self.client = nil
            return
        }
        // Session storage. On a signed device/TestFlight build the Keychain is the
        // secure, correct choice. On the SIMULATOR an unsigned build can't write the
        // Keychain (no entitlement), so the session would never persist and
        // `auth.session` would never resolve — silently dropping every authenticated
        // request to the anon role. Use a UserDefaults-backed store there so local
        // sign-in + sync work for development / verification.
        #if targetEnvironment(simulator)
        let sessionStorage: any AuthLocalStorage = UserDefaultsAuthStorage()
        #else
        let sessionStorage: any AuthLocalStorage = KeychainLocalStorage()
        #endif
        self.client = SupabaseClient(
            supabaseURL: config.backend.supabaseURL,
            supabaseKey: config.backend.supabasePublishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: sessionStorage,
                    redirectToURL: Self.authRedirectURL,
                    // PKCE is the SDK default and correct for the link-based
                    // invite flow; the OTP code path doesn't exercise it.
                    flowType: .pkce
                )
            )
        )
    }

    /// The auth backend seam, or nil in local-only mode.
    var authBackend: AuthBackend? {
        client.map(SupabaseAuthBackend.init)
    }

    /// Hands an inbound auth-callback URL to the SDK. No-op in local-only mode
    /// and for non-auth URLs (the SDK ignores URLs it can't parse as a session).
    /// The OTP code flow is the primary path; this exists so a link-based flow
    /// (e.g. invites) the next slice adds still completes its session exchange.
    func handleOpenURL(_ url: URL) {
        client?.auth.handle(url)
    }

    /// Awaits the active session so the SDK's PostgREST token resolver attaches
    /// the authenticated user's JWT to the NEXT data request.
    ///
    /// The SDK silently falls back to the anon key when `auth.session` isn't ready
    /// (it does `try? await getAccessToken()` and only overrides the Authorization
    /// header on success). Right after sign-in / launch the session can momentarily
    /// be unresolved, so the first households query would run as anon and RLS would
    /// return an EMPTY result — making the app think the user has no households and
    /// never starting sync. Calling this before the first authenticated query
    /// forces the session to resolve first. No-op in local-only mode.
    func ensureSessionReady() async {
        _ = try? await client?.auth.session
    }
}
