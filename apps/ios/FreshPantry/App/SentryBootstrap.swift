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
            let environment = config.environment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !environment.isEmpty {
                options.environment = environment
            }
        }
        #endif
    }
}
