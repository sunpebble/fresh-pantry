import CryptoKit
import Foundation

/// Deterministic, household-scoped sync ids for SET-MEMBERSHIP entities (收藏 /
/// 忌口) — where the logical key is "household H marks recipe R / keyword K", not
/// a per-action row.
///
/// Unlike the append-only entities (food log) that mint a fresh random UUID per
/// row, a set member must map to ONE stable row so two devices toggling the same
/// recipe converge on a single row (last-write-wins) instead of accumulating
/// duplicate rows that can't be cleanly un-toggled. The id is therefore DERIVED
/// from `(namespace, household, key)`:
/// - same inputs → same id on every device (cross-device dedupe),
/// - the household is folded into the hash, so two households marking the same
///   recipe get DISTINCT ids (no cross-household primary-key collision),
/// - the output is uuid-SHAPED (8-4-4-4-12 hex), so it passes
///   `ProposalApply.isUuid` and therefore travels the gateway's versioned-write /
///   soft-delete paths and fits a Postgres `uuid` primary-key column.
///
/// The id is NOT an RFC-4122 v4 uuid (no version/variant bits) — it doesn't need
/// to be: `isUuid` validates the hex shape only, and Postgres `uuid` accepts any
/// 128-bit value. The unit-separator (`U+001F`) between fields can never appear in
/// a household uuid, recipe id, or keyword, so the field concatenation is
/// injective (distinct inputs never collide before hashing).
enum SyncIdentity {
    static func deterministicUUID(namespace: String, household: String, key: String) -> String {
        let input = "\(namespace)\u{1F}\(household)\u{1F}\(key)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let b = Array(digest.prefix(16))
        return String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        )
    }
}
