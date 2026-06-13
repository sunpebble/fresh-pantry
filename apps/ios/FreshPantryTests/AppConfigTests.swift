import Foundation
import Testing
@testable import FreshPantry

/// Validates `AppConfig` parsing/validation matches the Flutter `BackendConfig`
/// / `SentryConfig` contract (required keys, defaults, URL + sample-rate rules).
struct AppConfigTests {
    private let minimal: [String: Any] = [
        "SUPABASE_URL": "https://ref.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
    ]

    @Test func requiresSupabaseURL() {
        #expect(throws: AppConfig.LoadError.self) {
            try AppConfig.parse(["SUPABASE_PUBLISHABLE_KEY": "k"])
        }
    }

    @Test func requiresPublishableKey() {
        #expect(throws: AppConfig.LoadError.self) {
            try AppConfig.parse(["SUPABASE_URL": "https://ref.supabase.co"])
        }
    }

    @Test func appliesDefaultsForOptionalKeys() throws {
        let config = try AppConfig.parse(minimal)
        #expect(config.backend.apiBaseURL == BackendConfig.defaultAPIBaseURL)
        #expect(config.sentry.dsn == SentryConfig.defaultDSN)
        #expect(config.sentry.tracesSampleRate == 1.0)
        // Session Replay defaults to on-error-only: no continuous session recording
        // (0.0), but a replay is still attached to every error/crash (1.0).
        #expect(config.sentry.replaySessionSampleRate == 0.0)
        #expect(config.sentry.replayOnErrorSampleRate == 1.0)
        #expect(config.sentry.environment.isEmpty)
    }

    @Test func rejectsNonHTTPSupabaseURL() {
        var dict = minimal
        dict["SUPABASE_URL"] = "ftp://nope"
        #expect(throws: AppConfig.LoadError.self) {
            try AppConfig.parse(dict)
        }
    }

    @Test func rejectsOutOfRangeSampleRate() {
        var dict = minimal
        dict["SENTRY_TRACES_SAMPLE_RATE"] = 2.0 as NSNumber
        #expect(throws: AppConfig.LoadError.self) {
            try AppConfig.parse(dict)
        }
    }

    @Test func honorsExplicitOverrides() throws {
        var dict = minimal
        dict["FRESH_PANTRY_API_BASE_URL"] = "https://api.example.test"
        dict["SENTRY_DSN"] = "https://abc@o1.ingest.sentry.io/1"
        dict["SENTRY_TRACES_SAMPLE_RATE"] = "0.25"
        let config = try AppConfig.parse(dict)
        #expect(config.backend.apiBaseURL.absoluteString == "https://api.example.test")
        #expect(config.sentry.dsn == "https://abc@o1.ingest.sentry.io/1")
        #expect(config.sentry.tracesSampleRate == 0.25)
    }
}
