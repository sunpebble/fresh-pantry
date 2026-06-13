import Foundation

/// Backend endpoints. Mirrors the Flutter `BackendConfig`: Supabase URL +
/// publishable key are required (no default), the API base URL has a default.
struct BackendConfig: Sendable, Equatable {
    let supabaseURL: URL
    let supabasePublishableKey: String
    let apiBaseURL: URL

    static let defaultAPIBaseURL = URL(string: "https://api.fresh-pantry.kunish.eu.org")!
}

/// Sentry/observability config. Mirrors the Flutter `SentryConfig`.
struct SentryConfig: Sendable, Equatable {
    let dsn: String
    let tracesSampleRate: Double
    let replaySessionSampleRate: Double
    let replayOnErrorSampleRate: Double
    let environment: String

    static let defaultDSN =
        "https://21d545f97f6b73ed79a31c666318ba7f@o848334.ingest.us.sentry.io/4511468203147264"
}

/// Resolved app configuration.
///
/// Loaded at launch from a bundled `Secrets.plist` (gitignored; generated from
/// CI secrets or copied from `Secrets.example.plist` for local dev). This
/// replaces Flutter's `--dart-define` build-time injection while preserving the
/// exact same keys, defaults, and validation rules.
struct AppConfig: Sendable, Equatable {
    let backend: BackendConfig
    let sentry: SentryConfig

    enum LoadError: Error, CustomStringConvertible {
        case missingSecretsFile
        case missing(String)
        case invalidURL(key: String, value: String)
        case invalidSampleRate(key: String, value: Double)

        var description: String {
            switch self {
            case .missingSecretsFile:
                return "Secrets.plist 未找到 — 从 Secrets.example.plist 复制并填入 Supabase 配置"
            case let .missing(key):
                return "\(key) 必填但缺失"
            case let .invalidURL(key, value):
                return "\(key) 不是合法 http(s) URL: \(value)"
            case let .invalidSampleRate(key, value):
                return "\(key) 必须在 0...1: \(value)"
            }
        }
    }

    /// Loads and validates config from a bundle's `Secrets.plist`.
    static func load(from bundle: Bundle = .main) throws -> AppConfig {
        guard
            let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = raw as? [String: Any]
        else {
            throw LoadError.missingSecretsFile
        }
        return try parse(dict)
    }

    static func parse(_ dict: [String: Any]) throws -> AppConfig {
        func string(_ key: String) -> String {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func requiredString(_ key: String) throws -> String {
            let value = string(key)
            guard !value.isEmpty else { throw LoadError.missing(key) }
            return value
        }
        func httpURL(_ key: String, _ value: String) throws -> URL {
            guard let url = URL(string: value), let scheme = url.scheme,
                  scheme == "http" || scheme == "https", url.host?.isEmpty == false
            else { throw LoadError.invalidURL(key: key, value: value) }
            return url
        }
        func sampleRate(_ key: String, default def: Double) throws -> Double {
            let raw = string(key)
            let value = (dict[key] as? NSNumber)?.doubleValue
                ?? (raw.isEmpty ? def : (Double(raw) ?? def))
            guard value.isFinite, value >= 0, value <= 1 else {
                throw LoadError.invalidSampleRate(key: key, value: value)
            }
            return value
        }

        let supabaseURLString = try requiredString("SUPABASE_URL")
        let backend = BackendConfig(
            supabaseURL: try httpURL("SUPABASE_URL", supabaseURLString),
            supabasePublishableKey: try requiredString("SUPABASE_PUBLISHABLE_KEY"),
            apiBaseURL: {
                let raw = string("FRESH_PANTRY_API_BASE_URL")
                return (try? httpURL("FRESH_PANTRY_API_BASE_URL", raw))
                    ?? BackendConfig.defaultAPIBaseURL
            }()
        )

        let dsn = string("SENTRY_DSN").isEmpty ? SentryConfig.defaultDSN : string("SENTRY_DSN")
        let sentry = SentryConfig(
            dsn: dsn,
            tracesSampleRate: try sampleRate("SENTRY_TRACES_SAMPLE_RATE", default: 1.0),
            // Session Replay: default to ON-ERROR ONLY (no continuous session
            // recording). Always-on replay (1.0) periodically captures a masked
            // view-hierarchy snapshot on the main thread — a recurring main-thread
            // cost — and burns replay quota. 0.0 keeps the high-value case (a replay
            // attached to every error/crash via the on-error rate below).
            // Secrets.plist carries no SENTRY_REPLAY_* key, so this default is what
            // ships; add the key only to override per build.
            replaySessionSampleRate: try sampleRate("SENTRY_REPLAY_SESSION_SAMPLE_RATE", default: 0.0),
            replayOnErrorSampleRate: try sampleRate("SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE", default: 1.0),
            environment: string("SENTRY_ENVIRONMENT")
        )

        return AppConfig(backend: backend, sentry: sentry)
    }
}
