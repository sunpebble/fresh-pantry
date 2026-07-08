import Foundation

/// Helpers for the per-household `updated_at` inbound-sync watermark.
enum SyncCursor {
    /// The latest `updated_at` across pulled rows (decoded maps carry the key
    /// only because `loadRows` re-stamps it via `stampUpdatedAt`).
    static func maxUpdatedAt(in rows: [[String: JSONValue]]) -> Date? {
        rows.compactMap { row -> Date? in
            guard case let .string(raw) = row["updated_at"] else { return nil }
            return JSONDate.parse(raw)
        }.max()
    }

    /// Advances `cursor` to the max `updated_at` seen in `rows`, if any.
    static func advance(_ cursor: Date?, with rows: [[String: JSONValue]]) -> Date? {
        guard let latest = maxUpdatedAt(in: rows) else { return cursor }
        guard let cursor else { return latest }
        return max(cursor, latest)
    }

    /// Re-stamps the raw row's `updated_at` onto its decoded domain map. The
    /// codecs only map declared columns, so decoding drops `updated_at` — and
    /// without this key `maxUpdatedAt` sees nothing, the watermark never
    /// advances, and incremental pulls stay permanent no-ops.
    static func stampUpdatedAt(
        _ domain: [String: JSONValue],
        from raw: [String: JSONValue]
    ) -> [String: JSONValue] {
        var stamped = domain
        stamped["updated_at"] = raw["updated_at"] ?? .null
        return stamped
    }
}
