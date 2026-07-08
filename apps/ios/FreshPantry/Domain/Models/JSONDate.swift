import Foundation

/// Date <-> JSON-string helpers mirroring Flutter's `sync_metadata.dart`
/// free functions and `DateTime.toIso8601String()` / `DateTime.tryParse`.
///
/// Parity notes:
/// - Encoding uses the Dart `toIso8601String()` shape: milliseconds always
///   present, UTC suffixed `Z`, local times without offset. We reproduce the
///   millisecond-precision form so payload bytes match the Flutter wire format.
/// - Decoding accepts the same inputs `DateTime.tryParse` does (ISO8601 with or
///   without fractional seconds / timezone), returning nil on blank / unparseable.
enum JSONDate {
    /// `dateTimeFromJsonValue`: nil unless `value` is a non-blank string, then a
    /// best-effort parse (which may itself still fail -> nil).
    static func fromJSONValue(_ value: Any?) -> Date? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return parse(string)
    }

    // MARK: Encoding

    /// Mirrors Dart `DateTime.toIso8601String()`: `yyyy-MM-ddTHH:mm:ss.SSS` with
    /// a trailing `Z` for UTC dates. Foundation `Date` carries no zone, so we
    /// always encode in UTC with the `Z` suffix (the Flutter model normalizes
    /// the sync-critical timestamps — loggedAt, deletedAt — to UTC already).
    ///
    /// already builds one for parsing). The formatter ROUNDS sub-millisecond
    /// fractions to the nearest ms; Dart `toIso8601String()` TRUNCATES, and the
    /// `.rounded(.down)` floor below matches it. Swapping in the formatter drifts
    /// ~50% of `Date()` outbox writes by one ms (and carries into the seconds
    /// field at the .9995 boundary), silently corrupting the sync wire bytes.
    /// Keep hand-rolled — a formatter would need the Date pre-truncated to whole
    /// ms first, which is more code, not less.
    static func iso8601(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let millis = Int((Double(components.nanosecond ?? 0) / 1_000_000).rounded(.down))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            millis
        )
    }

    // MARK: Decoding

    /// Best-effort ISO8601 parse mirroring `DateTime.tryParse`. Handles the
    /// fractional-second and zoned forms our encoder and the Flutter app emit.
    static func parse(_ raw: String) -> Date? {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.isEmpty { return nil }
        // Zoned ISO (with/without fractional seconds), e.g. "...Z" / "...+08:00".
        if let date = isoWithFraction.date(from: string) { return date }
        if let date = isoNoFraction.date(from: string) { return date }
        // Zoneless ISO (e.g. "2026-06-08T15:30:00[.SSS]"), parsed as LOCAL time —
        // matching Dart `DateTime.tryParse`, which produces a local DateTime for
        // a timestamp carrying no timezone designator.
        if let date = zonelessWithFraction.date(from: string) { return date }
        if let date = zonelessNoFraction.date(from: string) { return date }
        // Date-only ("yyyy-MM-dd") — used by MealPlanEntry's serialized key.
        if let date = dateOnly.date(from: string) { return date }
        return nil
    }

    // MARK: Formatters

    static let utc = TimeZone(identifier: "UTC")!

    // Formatters are configured once and only read afterwards. Apple's
    // date formatters are documented thread-safe for concurrent reads, so the
    // `nonisolated(unsafe)` opt-out is sound here.
    nonisolated(unsafe) private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func zonelessFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static let zonelessWithFraction = zonelessFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS")
    private static let zonelessNoFraction = zonelessFormatter("yyyy-MM-dd'T'HH:mm:ss")
}

/// `JSONValue` is a small AnyCodable-style box used so the domain structs can
/// round-trip the exact heterogeneous JSON shapes (nulls preserved, numbers vs
/// strings distinguished) that the Flutter `toJson()` maps produce. This keeps
/// `payloadJSON` byte-faithful for Supabase sync without leaning on Swift's
/// stricter `Codable` key-omission behavior.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
