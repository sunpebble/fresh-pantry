import Foundation
import os

/// The full backup payload: the Flutter-parity `BackupData` core plus the
/// iOS-only optional scopes. Defined at the codec boundary (not in
/// `Domain/Models`) because the optionality is a wire-format concern: a nil
/// field means "this scope's key was ABSENT from the blob" (a pre-expansion
/// backup) — the import side MUST skip the live scope then, never clear it,
/// or restoring an old backup would wipe data the blob never carried (e.g.
/// months of food-log history).
struct BackupArchive: Equatable, Sendable {
    var data: BackupData
    /// 减废账本 (用掉/浪费/抢救历史) — not rebuildable, the waste-stats truth source.
    var foodLog: [FoodLogEntry]?
    /// Favorite recipe ids (菜谱收藏).
    var favorites: [String]?
    /// 忌口 keywords, canonical (trimmed + lowercased) form.
    var dietaryExclusions: [String]?
    /// 饮食偏好 preset labels (高蛋白/低脂/素食/…).
    var dietPreferences: [String]?
    /// 到期提醒方案 (per-flag toggles + delivery time + quiet hours).
    var reminderSettings: ReminderSettings?

    init(
        data: BackupData,
        foodLog: [FoodLogEntry]? = nil,
        favorites: [String]? = nil,
        dietaryExclusions: [String]? = nil,
        dietPreferences: [String]? = nil,
        reminderSettings: ReminderSettings? = nil
    ) {
        self.data = data
        self.foodLog = foodLog
        self.favorites = favorites
        self.dietaryExclusions = dietaryExclusions
        self.dietPreferences = dietPreferences
        self.reminderSettings = reminderSettings
    }
}

/// Pure (de)serialization for backup blobs — no storage, network, or DI access.
/// It converts `BackupData` (live domain models) to/from a versioned,
/// pretty-printed JSON envelope. The orchestration that reads the live stores on
/// export and writes them on import lives in `BackupController`.
///
/// Version 2 stores structured domain-model lists. Version 1 stored raw
/// SharedPreferences string blobs keyed by legacy keys; after the offline-first
/// migration those keys are no longer the source of truth, so v1 export/import
/// silently lost data. v2 reads/writes the live repository-backed stores instead.
///
/// PARITY (invariant #8): `version == 2` ONLY (v1 + any other rejected); strict
/// decode-before-write so a malformed import can never partially overwrite live
/// data; `addHistory` round-trips as an opaque map; the food-details cache is
/// intentionally excluded. Envelope/payload key names + error messages mirror the
/// Flutter `BackupService` exactly.
///
/// The v2 payload is a SUPERSET of the Flutter-era contract: the original five
/// keys keep their exact names/shapes (old blobs stay importable), and the
/// iOS-only scopes (`foodLog`/`favorites`/`dietaryExclusions`/`dietPreferences`/
/// `reminderSettings`) ride along as OPTIONAL keys. The version stays 2 on
/// purpose — the additions are purely additive, and a bump would lock older app
/// builds out of new blobs they could otherwise read (they ignore unknown keys).
enum BackupService {
    static let backupVersion = 2

    /// Typed failures mirroring the Flutter `BackupVersionException` +
    /// `FormatException`s, with the same human-readable messages.
    enum BackupError: Error, Equatable {
        /// Missing / non-int / unsupported `version` (the version negotiation).
        case version(String)
        /// Malformed JSON or a wrong payload shape (the structural validation).
        case format(String)
    }

    // MARK: Encode

    /// Serializes live app data into a versioned, pretty-printed JSON blob.
    ///
    /// `exportedAt` is injectable so tests can pin the timestamp; production
    /// passes the default `Date()` and it is written as ISO8601 UTC.
    static func encode(_ archive: BackupArchive, exportedAt: Date = Date()) -> String {
        let data = archive.data
        var payload: [String: JSONValue] = [
            "inventory": list(data.inventory),
            "addHistory": map(data.addHistory),
            "shopping": list(data.shopping),
            "customRecipes": list(data.customRecipes),
            "mealPlan": list(data.mealPlan),
        ]
        if let aiSettings = data.aiSettings {
            payload["aiSettings"] = object(aiSettings)
        }
        // Optional iOS-only scopes: a nil field writes NO key (a core-only blob
        // is byte-identical to the pre-expansion output).
        if let foodLog = archive.foodLog {
            payload["foodLog"] = list(foodLog)
        }
        if let favorites = archive.favorites {
            payload["favorites"] = stringList(favorites)
        }
        if let dietaryExclusions = archive.dietaryExclusions {
            payload["dietaryExclusions"] = stringList(dietaryExclusions)
        }
        if let dietPreferences = archive.dietPreferences {
            payload["dietPreferences"] = stringList(dietPreferences)
        }
        if let reminderSettings = archive.reminderSettings {
            payload["reminderSettings"] = object(reminderSettings)
        }

        let envelope: JSONValue = .object([
            "version": .int(backupVersion),
            "exportedAt": .string(JSONDate.iso8601(exportedAt)),
            "data": .object(payload),
        ])

        return prettyPrinted(envelope)
    }

    // MARK: Decode

    /// Parses and structurally validates a backup blob into typed `BackupData`.
    ///
    /// Throws `BackupError.version` for a missing/unsupported version and
    /// `BackupError.format` for malformed JSON or wrong payload shapes. Because
    /// all parsing happens here BEFORE any caller writes, a failed decode can
    /// never partially overwrite existing data.
    static func decode(_ string: String) throws -> BackupData {
        try decodeArchive(string).data
    }

    /// Full decode including the optional iOS-only scopes. An absent/null key
    /// decodes as nil (NOT empty) so the import can tell "not backed up" (skip
    /// the live scope) from "backed up empty" (clear it).
    static func decodeArchive(_ string: String) throws -> BackupArchive {
        guard let data = string.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data)
        else {
            throw BackupError.format("Backup blob is not valid JSON")
        }
        guard let root = raw as? [String: Any] else {
            throw BackupError.format("Backup blob is not a JSON object")
        }
        guard let version = intValue(root["version"]) else {
            throw BackupError.version(
                "Missing or invalid version (got: \(describe(root["version"])))"
            )
        }
        guard version == backupVersion else {
            throw BackupError.version(
                "Unsupported backup version \(version) (expected \(backupVersion))"
            )
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw BackupError.format("Backup data is not a JSON object")
        }

        return BackupArchive(
            data: BackupData(
                inventory: try parseList(payload, "inventory", as: Ingredient.self),
                addHistory: try parseMap(payload, "addHistory"),
                shopping: try parseList(payload, "shopping", as: ShoppingItem.self),
                customRecipes: try parseList(payload, "customRecipes", as: Recipe.self),
                mealPlan: try parseList(payload, "mealPlan", as: MealPlanEntry.self),
                aiSettings: try parseAiSettings(payload)
            ),
            foodLog: try parseOptionalList(payload, "foodLog", as: FoodLogEntry.self),
            favorites: try parseOptionalStringList(payload, "favorites"),
            dietaryExclusions: try parseOptionalStringList(payload, "dietaryExclusions"),
            dietPreferences: try parseOptionalStringList(payload, "dietPreferences"),
            reminderSettings: try parseReminderSettings(payload)
        )
    }

    // MARK: Decode helpers (mirror the Dart `_parseList` / `_parseMap`)

    private static func parseList<T: Decodable>(
        _ payload: [String: Any],
        _ key: String,
        as type: T.Type
    ) throws -> [T] {
        // Core scopes are always written, so absent collapses to empty.
        try parseOptionalList(payload, key, as: type) ?? []
    }

    /// Presence-aware list parse for the optional scopes: a missing/null key is
    /// nil (scope absent from the blob), distinct from a present-but-empty list.
    private static func parseOptionalList<T: Decodable>(
        _ payload: [String: Any],
        _ key: String,
        as type: T.Type
    ) throws -> [T]? {
        let raw = payload[key]
        if raw == nil || raw is NSNull { return nil }
        guard let list = raw as? [Any] else {
            throw BackupError.format("Backup payload for \"\(key)\" must be a JSON list")
        }
        // whereType<Map> then fromJson: non-object elements are skipped, and a
        // structurally-valid object that fails to decode is dropped (lenient,
        // matching the per-row tolerance of the live repositories).
        return list.compactMap { element in
            guard let object = element as? [String: Any] else { return nil }
            return DomainJSON.fromValueMap(T.self, from: jsonValueMap(object))
        }
    }

    /// String-array scopes (favorites/忌口/偏好): missing/null → nil; a non-list
    /// is a format error; non-string elements are skipped (the same per-element
    /// tolerance as `parseList`). Normalization stays with the owning stores.
    private static func parseOptionalStringList(
        _ payload: [String: Any],
        _ key: String
    ) throws -> [String]? {
        let raw = payload[key]
        if raw == nil || raw is NSNull { return nil }
        guard let list = raw as? [Any] else {
            throw BackupError.format("Backup payload for \"\(key)\" must be a JSON list")
        }
        return list.compactMap { $0 as? String }
    }

    private static func parseMap(
        _ payload: [String: Any],
        _ key: String
    ) throws -> [String: AddHistoryEntry] {
        let raw = payload[key]
        if raw == nil || raw is NSNull { return [:] }
        guard let dictionary = raw as? [String: Any] else {
            throw BackupError.format("Backup payload for \"\(key)\" must be a JSON object")
        }
        var result: [String: AddHistoryEntry] = [:]
        for (name, value) in dictionary {
            guard let object = value as? [String: Any],
                  let entry = DomainJSON.fromValueMap(AddHistoryEntry.self, from: jsonValueMap(object))
            else { continue }
            result[name] = entry
        }
        return result
    }

    private static func parseAiSettings(_ payload: [String: Any]) throws -> AiSettings? {
        let raw = payload["aiSettings"]
        if raw == nil || raw is NSNull { return nil }
        guard let object = raw as? [String: Any] else {
            throw BackupError.format("Backup payload for \"aiSettings\" must be a JSON object")
        }
        return DomainJSON.fromValueMap(AiSettings.self, from: jsonValueMap(object))
    }

    private static func parseReminderSettings(_ payload: [String: Any]) throws -> ReminderSettings? {
        let raw = payload["reminderSettings"]
        if raw == nil || raw is NSNull { return nil }
        guard let object = raw as? [String: Any] else {
            throw BackupError.format("Backup payload for \"reminderSettings\" must be a JSON object")
        }
        return DomainJSON.fromValueMap(ReminderSettings.self, from: jsonValueMap(object))
    }

    // MARK: Encode helpers

    /// `[Encodable]` -> a `JSONValue` array of each element's `toJson()` map.
    private static func list<T: Encodable>(_ items: [T]) -> JSONValue {
        .array(items.map { object($0) })
    }

    /// A single `Encodable`'s `toJson()` map as a `JSONValue.object`.
    private static func object<T: Encodable>(_ value: T) -> JSONValue {
        guard let map = DomainJSON.valueMap(value) else { return .object([:]) }
        return .object(map)
    }

    /// `[String]` -> a plain JSON string array (the KV stores' wire shape).
    private static func stringList(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }

    /// The add-history frequency map -> a `JSONValue.object` of each entry's JSON.
    private static func map(_ history: [String: AddHistoryEntry]) -> JSONValue {
        .object(history.mapValues { object($0) })
    }

    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "backup")

    /// Pretty-prints a `JSONValue` envelope with 2-space indentation + sorted keys
    /// (Foundation's `.prettyPrinted` uses 2-space indent, matching Dart's
    /// `JsonEncoder.withIndent('  ')`; `.sortedKeys` makes the output stable).
    ///
    /// On serialization failure this returns `"{}"` (an empty-but-valid envelope)
    /// rather than throwing, so the export never crashes — but a `"{}"` backup is
    /// effectively empty and would fail restore validation. Log it so a silent
    /// empty backup is observable. NOTE: the proper fix is to make this `throws`
    /// and surface the failure at the export call site (tracked as follow-up).
    private static func prettyPrinted(_ value: JSONValue) -> String {
        guard let encoded = try? DomainJSON.encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else {
            logger.error("backup serialization failed — exported backup is EMPTY (\"{}\") and will not restore")
            return "{}"
        }
        return string
    }

    // MARK: JSON value bridging

    /// Re-decodes a `JSONSerialization` `[String: Any]` object into the strongly
    /// typed `[String: JSONValue]` the domain `fromValueMap` expects.
    private static func jsonValueMap(_ object: [String: Any]) -> [String: JSONValue] {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let map = try? DomainJSON.decoder.decode([String: JSONValue].self, from: data)
        else { return [:] }
        return map
    }

    /// Strict int extraction matching Dart's `version is! int`: a JSON int passes,
    /// a bool / double / string / absent value does NOT.
    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // Reject booleans (NSNumber bridges `true`/`false`) and non-integral doubles.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let type = String(cString: number.objCType)
        // Floating-point JSON numbers (e.g. 2.5) are not ints.
        if type == "d" || type == "f" { return nil }
        return number.intValue
    }

    private static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "null" }
        return String(describing: value)
    }
}
