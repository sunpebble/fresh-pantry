import Foundation

/// Pure local⇄remote reconciliation rule: remote rows are authoritative, and
/// only still-unsynced local rows survive alongside them.
///
/// Ported from the `_mergeRemoteXWithLocalOnly` + `_isLocalOnlyX` helpers in
/// `lib/sync/household_content_sync_coordinator.dart`. Kept SDK-free and pure so
/// the merge contract is unit-testable without SwiftData / Supabase.
///
/// For each entity the result is: every remote row, followed by the local rows
/// that are LOCAL-ONLY (never synced), NOT already present remotely by id, and
/// ALLOWED by the upload scope (no pending op claims them for another
/// household — parity invariant #7). Remote wins on id collisions, a synced
/// local row is dropped (remote is the source of truth), and a soft-deleted
/// local row is dropped (its remote absence already reflects the delete).
///
/// Generic over `SyncableEntity` (ADR-0004): the rule is written once, not copied
/// per entity. Soft-delete is `deletedAt != nil`; local-only/well-formed derive
/// from the protocol. Callers pass the entity's `SyncEntityType` for the scope
/// check.
enum HouseholdMergePolicy {
    /// Remote rows first, then the local-only rows absent remotely and allowed by
    /// the scope. Order is preserved (remote in load order, then the surviving
    /// locals in their original order).
    static func merge<T: SyncableEntity>(
        remote: [T],
        local: [T],
        scope: LocalUploadScope,
        entityType: SyncEntityType
    ) -> [T] {
        let remoteIds = Set(remote.map(\.id))
        let survivingLocals = local.filter { element in
            element.isLocalOnly
                && !remoteIds.contains(element.id)
                && scope.allows(entityType, element.id)
        }
        return remote + survivingLocals
    }

    /// Applies an incremental remote delta onto the local snapshot: tombstones
    /// drop synced rows, upserts replace by id, unseen locals are kept.
    static func patch<T: SyncableEntity>(remoteDelta: [T], local: [T]) -> [T] {
        var deltaById: [String: T] = [:]
        var deletedIds = Set<String>()
        for delta in remoteDelta {
            if delta.deletedAt != nil {
                deltaById.removeValue(forKey: delta.id)
                deletedIds.insert(delta.id)
            } else {
                deltaById[delta.id] = delta
                deletedIds.remove(delta.id)
            }
        }
        var merged: [T] = []
        var seen = Set<String>()
        for item in local {
            if deletedIds.contains(item.id) { continue }
            if let delta = deltaById[item.id], delta.deletedAt == nil {
                merged.append(delta)
            } else if deltaById[item.id] == nil {
                merged.append(item)
            }
            seen.insert(item.id)
        }
        for (itemId, delta) in deltaById where !seen.contains(itemId) {
            merged.append(delta)
        }
        return merged
    }
}
