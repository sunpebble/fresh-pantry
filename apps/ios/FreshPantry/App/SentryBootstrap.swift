import Foundation
#if !DEBUG
import Sentry
#endif

/// Starts the Sentry SDK from the resolved `SentryConfig`, mirroring the Flutter
/// `SentryFlutter.init` setup in `apps/mobile/lib/main.dart`:
///
/// - **DEBUG builds skip Sentry entirely.** Local errors already surface in the
///   console, so reporting them just pollutes the production issue stream with
///   developer-machine noise — parity with Flutter's `if (kDebugMode) return;`.
/// - Options mirror Flutter exactly: DSN, traces sample rate, session-replay
///   session / on-error sample rates, mask-all-text/images privacy, and an
///   `environment` only when non-empty (otherwise the SDK default applies).
///
/// `tracesSampleRate` is `NSNumber?` and the replay rates are `Float` in
/// sentry-cocoa, so the `Double`s from `SentryConfig` are converted explicitly.
enum SentryBootstrap {
    /// Initializes Sentry for release/profile builds. No-op in DEBUG, and when no
    /// config is available (local-only / OSS checkout without a `Secrets.plist`).
    static func start(_ config: SentryConfig?) {
        #if !DEBUG
        guard let config else { return }
        SentrySDK.start { options in
            options.dsn = config.dsn
            options.tracesSampleRate = NSNumber(value: config.tracesSampleRate)
            options.sessionReplay.sessionSampleRate = Float(config.replaySessionSampleRate)
            options.sessionReplay.onErrorSampleRate = Float(config.replayOnErrorSampleRate)
            options.sessionReplay.maskAllText = true
            options.sessionReplay.maskAllImages = true
            // Only report failed HTTP requests to our own backend (Supabase, incl.
            // Storage covers — same host). Third-party services like
            // world.openfoodfacts.org return transient 5xx we already handle
            // gracefully → reporting them is pure Sentry noise (FRESH_PANTRY-12).
            // failedRequestTargets is [Any]; a String element is matched as a URL
            // substring. Default is the regex ".*" (every host).
            options.failedRequestTargets = ["nkugeupizmphbeicykpj.supabase.co"]
            // App Hang Tracking. On iOS, sentry-cocoa 9.17.1 already uses the V2 ANR
            // tracker (SentryANRTrackerV2) unconditionally — there is NO
            // `enableAppHangTrackingV2` flag (do not add one; it won't compile).
            // Pin the contract explicitly so the watchdog-class hangs
            // (FRESH_PANTRY-13/14) capture a usable blocking stack going forward
            // instead of the bare run-loop (mach_msg) the old V1 produced.
            options.enableAppHangTracking = true                // default true
            options.appHangTimeoutInterval = 2.0                // default 2.0s
            options.enableReportNonFullyBlockingAppHangs = true // default true (~0.8s case)
            let environment = config.environment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !environment.isEmpty {
                options.environment = environment
            }
        }
        #endif
    }
}
