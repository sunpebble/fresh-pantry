import Foundation

/// The single home for the Supabase ⇄ domain row mapping. Ported from
/// `lib/sync/remote_row_codec.dart`.
///
/// Each content entity's columns are declared once as a `Column` list; both the
/// decode (Supabase row → domain JSON map) and encode (domain JSON map →
/// Supabase row) directions derive from that one list, so renaming a column is a
/// one-line change instead of two functions to keep in sync. The round-trip is
/// pinned by `RemoteRowCodecTests`.
///
/// Both the Supabase row (snake_case columns) and the domain map (camelCase keys
/// matching the domain models' Codable output) are `[String: JSONValue]`, which
/// keeps this codec SDK-free: the SDK layer converts its responses to
/// `[String: JSONValue]` before calling in, and serializes our upsert rows back
/// out. To match the Flutter wire format — Dart `toJson()` always emits a key
/// (with a `null` value) rather than omitting it — every mapped key is written
/// in BOTH directions, with absent/null columns normalized to `.null`. The one
/// exception is `id`, handled outside the table: always read on decode, written
/// on encode only when it is a sync UUID (so the database `gen_random_uuid()`
/// default fills local-only ids).
enum RemoteRowCodec {
    // MARK: - Version coercion

    /// Local rows start at version 1; an upsert never writes version 0 (which
    /// would be read back as "local-only" and re-uploaded forever). Mirrors Dart
    /// `versionForUpsert`: a non-numeric `remoteVersion` floors to 0 first, then
    /// `<= 0` becomes 1.
    static func versionForUpsert(_ remoteVersion: JSONValue?) -> Int {
        let version = intValue(remoteVersion, default: 0)
        return version <= 0 ? 1 : version
    }

    // MARK: - Local id gating

    /// Mirrors Dart `_applyLocalId`: write `id` ONLY when it is a `.string` whose
    /// value passes the canonical UUID shape check. Otherwise leave it out so the
    /// database `gen_random_uuid()` default fills the local-only id.
    static func applyLocalId(_ row: inout [String: JSONValue], id: JSONValue?) {
        guard case let .string(value) = id, ProposalApply.isUuid(value) else { return }
        row["id"] = .string(value)
    }

    // MARK: - Per-entity codecs (column tables)

    /// inventory_items ⇄ Ingredient map.
    static func inventoryRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        inventoryRowMap.fromRow(row)
    }

    static func inventoryRowForUpsert(
        householdID: String,
        item: [String: JSONValue]
    ) -> [String: JSONValue] {
        inventoryRowMap.toRow(householdID: householdID, item: item)
    }

    /// shopping_items ⇄ ShoppingItem map.
    static func shoppingRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        shoppingRowMap.fromRow(row)
    }

    static func shoppingRowForUpsert(
        householdID: String,
        item: [String: JSONValue]
    ) -> [String: JSONValue] {
        shoppingRowMap.toRow(householdID: householdID, item: item)
    }

    // MARK: - Per-entity codecs (payload blob)

    /// custom_recipes ⇄ Recipe map. Custom recipes carry their fields in an
    /// opaque `payload` jsonb blob rather than as columns, so only `id` and the
    /// sync columns are real columns.
    static func customRecipeRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        payloadRowFromJson(row)
    }

    static func customRecipeRowForUpsert(
        householdID: String,
        recipe: [String: JSONValue]
    ) -> [String: JSONValue] {
        payloadRowForUpsert(householdID: householdID, domain: recipe)
    }

    /// meal_plan_entries ⇄ MealPlanEntry map. Same opaque-`payload` shape as
    /// custom recipes — only `id` and the sync columns are real columns.
    static func mealPlanEntryRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        payloadRowFromJson(row)
    }

    static func mealPlanEntryRowForUpsert(
        householdID: String,
        entry: [String: JSONValue]
    ) -> [String: JSONValue] {
        payloadRowForUpsert(householdID: householdID, domain: entry)
    }

    /// food_log_entries ⇄ FoodLogEntry map. Same opaque-`payload` shape as
    /// meal plans — only `id` and the sync columns are real columns.
    static func foodLogEntryRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        payloadRowFromJson(row)
    }

    static func foodLogEntryRowForUpsert(
        householdID: String,
        entry: [String: JSONValue]
    ) -> [String: JSONValue] {
        payloadRowForUpsert(householdID: householdID, domain: entry)
    }
}

// MARK: - Column table

extension RemoteRowCodec {
    /// One column's mapping. `column` is the snake_case Supabase name, `key` the
    /// camelCase domain key. `decode`/`encode` apply per-direction defaults and
    /// type coercions; a nil transform passes the value through unchanged.
    ///
    /// `Transform` takes the value as it appears in the source map — `nil` when
    /// the key is absent, `.null` when the key is present but null — and returns
    /// the value to write (always written, mirroring Dart's `map[k] = v`).
    fileprivate struct Column: Sendable {
        /// `@Sendable` so the column tables can be global `static let`s under
        /// Swift 6 strict concurrency — every transform is a capture-free
        /// reference to a `static func`, which satisfies it trivially.
        typealias Transform = @Sendable (JSONValue?) -> JSONValue

        let column: String
        let key: String
        let decode: Transform?
        let encode: Transform?

        init(_ column: String, _ key: String, decode: Transform? = nil, encode: Transform? = nil) {
            self.column = column
            self.key = key
            self.decode = decode
            self.encode = encode
        }
    }

    /// Decodes/encodes a row whose columns map straight onto domain keys.
    fileprivate struct RowMap: Sendable {
        let columns: [Column]

        /// Supabase row → domain map. Starts from the read-through `id`, then
        /// applies each column's decode (or passes the raw value through). A
        /// missing column becomes `.null` so the output key set is pinned.
        func fromRow(_ row: [String: JSONValue]) -> [String: JSONValue] {
            var domain: [String: JSONValue] = ["id": row["id"] ?? .null]
            for c in columns {
                let raw = row[c.column]
                domain[c.key] = c.decode?(raw) ?? raw ?? .null
            }
            return domain
        }

        /// Domain map → Supabase row. Starts from `household_id`, then applies
        /// each column's encode (or passes the raw value through), and finally
        /// writes `id` only when it is a sync UUID.
        func toRow(householdID: String, item: [String: JSONValue]) -> [String: JSONValue] {
            var row: [String: JSONValue] = ["household_id": .string(householdID)]
            for c in columns {
                let raw = item[c.key]
                row[c.column] = c.encode?(raw) ?? raw ?? .null
            }
            RemoteRowCodec.applyLocalId(&row, id: item["id"])
            return row
        }
    }
}

// MARK: - Per-direction value transforms

extension RemoteRowCodec {
    /// Defaults a null/absent string-ish value to empty string.
    fileprivate static func orEmpty(_ v: JSONValue?) -> JSONValue { isNull(v) ? .string("") : v! }

    /// Defaults a null/absent state to "fresh".
    fileprivate static func orFresh(_ v: JSONValue?) -> JSONValue { isNull(v) ? .string("fresh") : v! }

    /// Defaults a null/absent storage to "fridge" (encode direction only).
    fileprivate static func orFridge(_ v: JSONValue?) -> JSONValue { isNull(v) ? .string("fridge") : v! }

    /// Defaults a null/absent freshness to 1.0, leaving an existing value as-is.
    fileprivate static func orOne(_ v: JSONValue?) -> JSONValue { isNull(v) ? .double(1.0) : v! }

    /// Defaults a null/absent category to "其他".
    fileprivate static func orOther(_ v: JSONValue?) -> JSONValue { isNull(v) ? .string("其他") : v! }

    /// Defaults a null/absent checked flag to false.
    fileprivate static func orFalse(_ v: JSONValue?) -> JSONValue { isNull(v) ? .bool(false) : v! }

    /// Defaults a null/absent value to an empty JSON array (encode of `tags` so the
    /// not-null jsonb column never receives null).
    fileprivate static func orEmptyArray(_ v: JSONValue?) -> JSONValue { isNull(v) ? .array([]) : v! }

    /// Coerces any numeric encoding to a Double, defaulting null/non-numeric to
    /// 1.0 (decode of `freshness_percent`).
    fileprivate static func toDouble1(_ v: JSONValue?) -> JSONValue {
        .double(doubleValue(v, default: 1.0))
    }

    /// Coerces any numeric encoding to an Int, defaulting null/non-numeric to 0
    /// (decode of `version`).
    fileprivate static func toInt0(_ v: JSONValue?) -> JSONValue {
        .int(intValue(v, default: 0))
    }

    // MARK: Numeric extraction

    /// `(value as num?)?.toInt() ?? default` — `.int` as-is, `.double` truncated
    /// toward zero (Dart `num.toInt()`), everything else the fallback.
    fileprivate static func intValue(_ value: JSONValue?, default fallback: Int) -> Int {
        switch value {
        case let .int(n): return n
        case let .double(d): return Int(d) // truncates toward zero, like Dart toInt()
        default: return fallback
        }
    }

    /// `(value as num?)?.toDouble() ?? default` — both numeric cases widen to
    /// Double, everything else the fallback.
    fileprivate static func doubleValue(_ value: JSONValue?, default fallback: Double) -> Double {
        switch value {
        case let .double(d): return d
        case let .int(n): return Double(n)
        default: return fallback
        }
    }

    /// Treats both an absent key (`nil`) and a present-null value (`.null`) as
    /// "no value", matching Dart where a missing map entry and an explicit null
    /// both read as `null`.
    fileprivate static func isNull(_ value: JSONValue?) -> Bool {
        value == nil || value == .null
    }
}

// MARK: - Column tables

extension RemoteRowCodec {
    /// Sync columns common to every content entity.
    fileprivate static let versionCol = Column(
        "version", "remoteVersion", decode: toInt0, encode: { .int(versionForUpsert($0)) }
    )
    fileprivate static let clientUpdatedCol = Column("client_updated_at", "clientUpdatedAt")
    fileprivate static let deletedCol = Column("deleted_at", "deletedAt")

    fileprivate static let inventoryRowMap = RowMap(columns: [
        Column("name", "name"),
        Column("quantity", "quantity"),
        Column("unit", "unit"),
        Column("image_url", "imageUrl", decode: orEmpty, encode: orEmpty),
        Column("freshness_percent", "freshnessPercent", decode: toDouble1, encode: orOne),
        Column("state", "state", decode: orFresh, encode: orFresh),
        Column("expiry_label", "expiryLabel"),
        Column("category", "category"),
        Column("barcode", "barcode"),
        Column("storage", "storage", encode: orFridge),
        Column("expiry_date", "expiryDate"),
        Column("added_at", "addedAt"),
        Column("shelf_life_days", "shelfLifeDays"),
        // jsonb array ⇄ [String]. Encode defaults null/absent to an empty array so
        // the not-null `tags` column is always satisfied; decode passes through
        // (the domain model's lenient decode turns null into []).
        Column("tags", "tags", encode: orEmptyArray),
        versionCol,
        clientUpdatedCol,
        deletedCol,
    ])

    fileprivate static let shoppingRowMap = RowMap(columns: [
        Column("name", "name"),
        Column("detail", "detail", decode: orEmpty, encode: orEmpty),
        Column("image_url", "imageUrl"),
        Column("category", "category", decode: orOther, encode: orOther),
        Column("is_checked", "isChecked", decode: orFalse, encode: orFalse),
        versionCol,
        clientUpdatedCol,
        deletedCol,
    ])
}

// MARK: - Payload-blob codec

extension RemoteRowCodec {
    /// Supabase payload-row → domain map: spreads the `payload` blob, then
    /// overrides id and the sync columns from their real columns. Mirrors the
    /// Dart `customRecipeRowFromJson` / `mealPlanEntryRowFromJson` (identical
    /// shape). A missing/non-object payload yields an empty base map.
    fileprivate static func payloadRowFromJson(_ row: [String: JSONValue]) -> [String: JSONValue] {
        var domain: [String: JSONValue]
        if case let .object(payload) = row["payload"] {
            domain = payload
        } else {
            domain = [:]
        }
        // `id = row['id'] ?? payload['id']` — fall back to the payload's own id
        // when the row column is absent/null.
        let rowId = row["id"]
        domain["id"] = isNull(rowId) ? (domain["id"] ?? .null) : rowId!
        domain["remoteVersion"] = toInt0(row["version"])
        domain["clientUpdatedAt"] = row["client_updated_at"] ?? .null
        domain["deletedAt"] = row["deleted_at"] ?? .null
        return domain
    }

    /// Domain map → Supabase payload-row: the entire domain object lives in the
    /// single jsonb `payload` column, with the sync columns lifted out alongside.
    /// Mirrors the Dart `customRecipeRowForUpsert` / `mealPlanEntryRowForUpsert`.
    fileprivate static func payloadRowForUpsert(
        householdID: String,
        domain: [String: JSONValue]
    ) -> [String: JSONValue] {
        var row: [String: JSONValue] = [
            "household_id": .string(householdID),
            "payload": .object(domain),
            "version": .int(versionForUpsert(domain["remoteVersion"])),
            "client_updated_at": domain["clientUpdatedAt"] ?? .null,
            "deleted_at": domain["deletedAt"] ?? .null,
        ]
        applyLocalId(&row, id: domain["id"])
        return row
    }
}
