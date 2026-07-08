import Foundation
import os
import Supabase

/// The PUSH engine: drains the outbox to Supabase with optimistic-concurrency
/// version gating + client-wins conflict resolution. Ported from
/// `lib/sync/supabase_sync_gateway.dart`. Conforms to `RemoteSyncGateway`.
///
/// PARITY-CRITICAL CONTRACT:
/// - FIFO + stop-on-first-failure: `pushOperations` processes ops in order,
///   BREAKS on the first error, and returns ONLY the ids acknowledged BEFORE the
///   break. The coordinator removes exactly that set, so a re-order or partial-ack
///   mismatch would drop or double-apply writes.
/// - `version` is the optimistic lock: every content write sets `version` and
///   gates the UPDATE on `.eq("version", expected)`. First writes
///   (`baseVersion <= 0`) use `upsert(ignoreDuplicates: true)` so they never
///   downgrade an existing remote row; `versionForUpsert` never writes 0. A
///   conflicted first write (DO NOTHING → empty representation) is NOT success:
///   deterministic-id rows (favorite_recipes / dietary_preferences) collide
///   with live rows or tombstones the pull filtered out, so it falls through
///   to the contended-write resolution instead of silently acking a no-op.
///   Exception: when no remote row carries the op's id, the conflict was a
///   SECONDARY unique index (inventory's dedupe, migration 20260601035956) and
///   the silent skip is the designed outcome — resolved by acking, not writing.
///   This conflict check is an iOS-side fix the Dart client does not have yet.
/// - Conflict policy = client-patch-wins at the field level; conflicts are only
///   REPORTED (telemetry), never block — via `MergePolicy.mergeRemotePatch`.
/// - Soft delete only (sets `deleted_at`, never a hard delete).
///
/// Supabase Swift note: `update`/`upsert` default `returning: .representation`,
/// so the modified rows come back in the response body — we decode them with
/// `.execute().value` to detect a 0-row (contended) conditional update. We do NOT
/// chain `.select()` after `.update()` (that method lives on the query builder,
/// not the post-update filter builder).
actor SupabaseSyncGateway: RemoteSyncGateway {
    private let client: SupabaseClient
    private let diagnostics: Diagnostics
    private static let maxConflictRetries = 3
    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "sync")

    init(client: SupabaseClient, diagnostics: Diagnostics = NoopDiagnostics()) {
        self.client = client
        self.diagnostics = diagnostics
    }

    // MARK: - Push loop

    /// Pushes `ops` in order, stopping at the first failure. Returns the ids that
    /// were acknowledged before any failure (the coordinator drops exactly those).
    /// Never throws: a push error is reported and breaks the loop so the FIFO
    /// order is preserved for the next trigger.
    func pushOperations(_ ops: [SyncOperation]) async throws -> Set<String> {
        diagnostics.breadcrumb("sync.push_batch", ["count": String(ops.count)])
        var acknowledged: Set<String> = []
        for op in ops {
            do {
                try await pushOperation(op)
            } catch {
                reportPushError(op, error)
                break
            }
            acknowledged.insert(op.id)
        }
        return acknowledged
    }

    private func pushOperation(_ op: SyncOperation) async throws {
        switch op.entityType {
        case .inventoryItem:
            switch op.operation {
            case .create, .update, .intake, .deduction:
                try await pushVersionedRow(table: "inventory_items", op: op, codec: .inventory)
            case .delete:
                try await softDeleteRemoteRow(table: "inventory_items", op: op)
            case .toggleChecked:
                return // inventory has no checked flag
            }
        case .shoppingItem:
            switch op.operation {
            case .create, .update, .intake, .deduction:
                try await pushVersionedRow(table: "shopping_items", op: op, codec: .shopping)
            case .toggleChecked:
                let checked: JSONValue = op.patch["isChecked"] == .bool(true) ? .bool(true) : .bool(false)
                try await updateRemoteRow(table: "shopping_items", op: op, patch: ["is_checked": checked])
            case .delete:
                try await softDeleteRemoteRow(table: "shopping_items", op: op)
            }
        case .customRecipe:
            switch op.operation {
            case .create, .update:
                try await pushVersionedRow(table: "custom_recipes", op: op, codec: .customRecipe)
            case .delete:
                try await softDeleteRemoteRow(table: "custom_recipes", op: op)
            case .intake, .deduction, .toggleChecked:
                return
            }
        case .mealPlanEntry:
            switch op.operation {
            case .create, .update:
                try await pushVersionedRow(table: "meal_plan_entries", op: op, codec: .mealPlan)
            case .delete:
                try await softDeleteRemoteRow(table: "meal_plan_entries", op: op)
            case .intake, .deduction, .toggleChecked:
                return
            }
        case .foodLogEntry:
            switch op.operation {
            case .create, .update:
                try await pushVersionedRow(table: "food_log_entries", op: op, codec: .foodLog)
            case .delete:
                try await softDeleteRemoteRow(table: "food_log_entries", op: op)
            case .intake, .deduction, .toggleChecked:
                return
            }
        case .favoriteRecipe:
            switch op.operation {
            case .create, .update:
                try await pushVersionedRow(table: "favorite_recipes", op: op, codec: .favoriteRecipe)
            case .delete:
                try await softDeleteRemoteRow(table: "favorite_recipes", op: op)
            case .intake, .deduction, .toggleChecked:
                return
            }
        case .dietaryPreference:
            switch op.operation {
            case .create, .update:
                try await pushVersionedRow(table: "dietary_preferences", op: op, codec: .dietaryPreference)
            case .delete:
                try await softDeleteRemoteRow(table: "dietary_preferences", op: op)
            case .intake, .deduction, .toggleChecked:
                return
            }
        case .householdConfig:
            return // pushed via household table ops, not the outbox
        }
    }

    // MARK: - Versioned full-row write

    /// Mirrors Dart `_pushVersionedRow`, except the conflicted-first-write check
    /// (added here; the Dart client still acks a DO-NOTHING create as success).
    /// A first write (`baseVersion <= 0`) is an `upsert(ignoreDuplicates: true)`
    /// that treats a conflict on its OWN id as contention, not success; a
    /// subsequent write is a conditional UPDATE gated on the base version. Both
    /// fall back to a 3-way merge on contention.
    private func pushVersionedRow(table: String, op: SyncOperation, codec: EntityCodec) async throws {
        let entityId = resolvedEntityId(op)
        var domain = op.patch
        domain["id"] = .string(entityId)
        domain["clientUpdatedAt"] = .string(JSONDate.iso8601(op.createdAt))
        let baseVersion = op.baseVersion ?? 0

        if baseVersion <= 0 {
            domain["remoteVersion"] = .int(1)
            var row = codec.rowForUpsert(op.householdId, domain)
            row["client_id"] = .string(op.clientId)
            let inserted: [[String: AnyJSON]] = try await client.from(table)
                .upsert(SyncJSONBridge.toAnyObject(row), ignoreDuplicates: true)
                .execute()
                .value
            if inserted.isEmpty {
                // ON CONFLICT DO NOTHING wrote nothing. A non-UUID id was never
                // sent (`applyLocalId` drops it), so that conflict can only be a
                // secondary unique index (inventory's dedupe) — the documented
                // silent skip; resolving would feed a non-uuid into a uuid filter.
                guard ProposalApply.isUuid(entityId) else { return }
                // A UUID-id conflict is usually a deterministic-id row (favorite /
                // dietary) colliding with a tombstone this client never pulled.
                // Acking would silently drop the write; resolve against the live
                // row instead (the client-wins merge writes `deleted_at: null`,
                // so a tombstone is revived with a version-gated UPDATE).
                try await resolveContendedWrite(table: table, op: op, entityId: entityId, codec: codec)
            }
            return
        }

        guard ProposalApply.isUuid(entityId) else {
            throw SyncGatewayError.nonUuidVersionedWrite(entityId)
        }
        domain["remoteVersion"] = .int(baseVersion + 1)
        var row = codec.rowForUpsert(op.householdId, domain)
        row["client_id"] = .string(op.clientId)
        let updated: [[String: AnyJSON]] = try await client.from(table)
            .update(SyncJSONBridge.toAnyObject(row))
            .eq("household_id", value: op.householdId)
            .eq("id", value: entityId)
            .eq("version", value: baseVersion)
            .execute()
            .value
        if !updated.isEmpty { return }
        try await resolveContendedWrite(table: table, op: op, entityId: entityId, codec: codec)
    }

    /// Mirrors Dart `_resolveContendedWrite`: re-fetch the live row, recreate it if
    /// gone, else 3-way merge (client-wins) and conditionally write against the
    /// ACTUAL remote version, retrying up to `maxConflictRetries`.
    private func resolveContendedWrite(
        table: String,
        op: SyncOperation,
        entityId: String,
        codec: EntityCodec
    ) async throws {
        let localPatch = op.patch
        var recreateConflicted = false
        for _ in 0..<Self.maxConflictRetries {
            let current: [[String: AnyJSON]] = try await client.from(table)
                .select()
                .eq("household_id", value: op.householdId)
                .eq("id", value: entityId)
                .limit(1)
                .execute()
                .value

            guard let currentRow = current.first else {
                if recreateConflicted {
                    // The upsert conflicted yet no row carries our id: the
                    // collision is a secondary unique index (inventory's dedupe,
                    // migration 20260601035956), not the PK — the documented
                    // silent skip. Ack without writing.
                    return
                }
                // Row deleted / never created: recreate with an advanced version.
                var domain = op.patch
                domain["id"] = .string(entityId)
                domain["clientUpdatedAt"] = .string(JSONDate.iso8601(op.createdAt))
                domain["remoteVersion"] = .int((op.baseVersion ?? 0) + 1)
                var row = codec.rowForUpsert(op.householdId, domain)
                row["client_id"] = .string(op.clientId)
                let inserted: [[String: AnyJSON]] = try await client.from(table)
                    .upsert(SyncJSONBridge.toAnyObject(row), ignoreDuplicates: true)
                    .execute()
                    .value
                if inserted.isEmpty { recreateConflicted = true; continue }
                return
            }
            recreateConflicted = false

            let remoteRow = SyncJSONBridge.fromAnyObject(currentRow)
            let remoteVersion = intValue(remoteRow["version"], default: 0)
            let remoteDomain = codec.rowFromJson(remoteRow)
            let merge = MergePolicy.mergeRemotePatch(
                local: localPatch,
                remote: remoteDomain,
                patch: localPatch,
                baseVersion: op.baseVersion,
                remoteVersion: remoteVersion
            )
            if merge.conflict {
                reportConflict(op, fields: merge.conflictFields)
            }

            var merged = merge.value
            merged["id"] = .string(entityId)
            merged["remoteVersion"] = .int(remoteVersion + 1)
            merged["clientUpdatedAt"] = .string(JSONDate.iso8601(op.createdAt))
            var row = codec.rowForUpsert(op.householdId, merged)
            row["client_id"] = .string(op.clientId)
            let updated: [[String: AnyJSON]] = try await client.from(table)
                .update(SyncJSONBridge.toAnyObject(row))
                .eq("household_id", value: op.householdId)
                .eq("id", value: entityId)
                .eq("version", value: remoteVersion)
                .execute()
                .value
            if !updated.isEmpty { return }
        }
        throw SyncGatewayError.conflictUnresolved(entityId)
    }

    // MARK: - Upload PK-collision resolution

    /// Resolves `uploadLocalOnly` primary-key collisions — upload rows whose
    /// bulk `upsert(ignoreDuplicates:)` was DO-NOTHING'd on their own UUID id.
    /// Per row: select the remote row; a TOMBSTONE is revived with the row's
    /// content via the version-gated client-wins UPDATE (the pull filters
    /// tombstones, so nothing else can deliver it); a LIVE row is left
    /// untouched — remote is authoritative and the pull adopts it, preserving
    /// the missed-version-bump bump-v1 self-heal AND never overwriting a
    /// newer write a concurrent outbox push already landed; an ABSENT row is
    /// the secondary-unique-index dedupe skip (documented, see
    /// `pushVersionedRow`). Returns the row ids now safe to mark
    /// `remoteVersion = 1`; rows whose gated revive kept missing (hot row) or
    /// errored stay out and retry on the next sync run. Never throws.
    func resolveUploadCollisions(
        entityType: SyncEntityType,
        householdId: String,
        rows: [[String: JSONValue]],
        clientId: String
    ) async -> Set<String> {
        guard let binding = Self.contentBinding(entityType) else { return [] }
        var resolved: Set<String> = []
        for row in rows {
            guard case let .string(entityId) = row["id"] else { continue }
            do {
                if try await reviveIfTombstone(
                    table: binding.table,
                    codec: binding.codec,
                    householdId: householdId,
                    entityId: entityId,
                    row: row,
                    clientId: clientId
                ) {
                    resolved.insert(entityId)
                }
            } catch {
                Self.logger.error(
                    "upload-collision resolution failed \(entityType.rawValue, privacy: .public) id=\(entityId, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                diagnostics.failure("sync.upload_collision", error: error, ["entityType": entityType.rawValue])
            }
        }
        return resolved
    }

    /// One collided row's resolution. Only a tombstone is ever written — the
    /// same version-gated client-wins UPDATE `resolveContendedWrite` uses to
    /// revive one (a first write has no base to 3-way merge against, so the
    /// row's own content IS the client-wins result). Returns whether the row
    /// may be marked synced.
    private func reviveIfTombstone(
        table: String,
        codec: EntityCodec,
        householdId: String,
        entityId: String,
        row: [String: JSONValue],
        clientId: String
    ) async throws -> Bool {
        for _ in 0..<Self.maxConflictRetries {
            let current: [[String: AnyJSON]] = try await client.from(table)
                .select()
                .eq("household_id", value: householdId)
                .eq("id", value: entityId)
                .limit(1)
                .execute()
                .value
            guard let currentRow = current.first else {
                // No row carries the id: the conflict was a secondary unique
                // index (inventory's dedupe) — the documented silent skip.
                return true
            }
            let remoteRow = SyncJSONBridge.fromAnyObject(currentRow)
            guard case .string = remoteRow["deleted_at"] else {
                // Live row: remote is authoritative and the pull adopts it —
                // never overwrite (a concurrent outbox push may have just
                // landed a NEWER write here). The bump-v1 self-heal upstream
                // covers the missed-version-bump case.
                return true
            }
            let remoteVersion = intValue(remoteRow["version"], default: 0)
            var domain = row
            domain["remoteVersion"] = .int(remoteVersion + 1)
            var wire = codec.rowForUpsert(householdId, domain)
            wire["client_id"] = .string(clientId)
            let updated: [[String: AnyJSON]] = try await client.from(table)
                .update(SyncJSONBridge.toAnyObject(wire))
                .eq("household_id", value: householdId)
                .eq("id", value: entityId)
                .eq("version", value: remoteVersion)
                .execute()
                .value
            if !updated.isEmpty { return true }
        }
        return false
    }

    /// The content table + codec a `SyncEntityType`'s versioned rows live in.
    private static func contentBinding(_ entityType: SyncEntityType) -> (table: String, codec: EntityCodec)? {
        switch entityType {
        case .inventoryItem: ("inventory_items", .inventory)
        case .shoppingItem: ("shopping_items", .shopping)
        case .customRecipe: ("custom_recipes", .customRecipe)
        case .mealPlanEntry: ("meal_plan_entries", .mealPlan)
        case .foodLogEntry: ("food_log_entries", .foodLog)
        case .favoriteRecipe: ("favorite_recipes", .favoriteRecipe)
        case .dietaryPreference: ("dietary_preferences", .dietaryPreference)
        case .householdConfig: nil
        }
    }

    // MARK: - Soft delete + partial-column write

    private func softDeleteRemoteRow(table: String, op: SyncOperation) async throws {
        let deletedAt: String
        if case let .string(value) = op.patch["deletedAt"] {
            deletedAt = value
        } else {
            deletedAt = JSONDate.iso8601(op.createdAt)
        }
        try await updateRemoteRow(table: table, op: op, patch: ["deleted_at": .string(deletedAt)])
    }

    /// Mirrors Dart `_updateRemoteRow`: a partial-column patch (toggleChecked /
    /// soft-delete). Requires a UUID entity id (a local-only row can't be patched
    /// remotely), gates on the base version, then retries against the live version.
    private func updateRemoteRow(table: String, op: SyncOperation, patch: [String: JSONValue]) async throws {
        guard ProposalApply.isUuid(op.entityId) else {
            throw SyncGatewayError.nonUuidPartialWrite(op.entityId)
        }
        let baseVersion = op.baseVersion ?? 0
        let clientUpdatedAt = JSONDate.iso8601(op.createdAt)

        if baseVersion > 0 {
            let row = versionedPatch(patch, version: baseVersion + 1, op: op, clientUpdatedAt: clientUpdatedAt)
            let updated: [[String: AnyJSON]] = try await client.from(table)
                .update(SyncJSONBridge.toAnyObject(row))
                .eq("household_id", value: op.householdId)
                .eq("id", value: op.entityId)
                .eq("version", value: baseVersion)
                .execute()
                .value
            if !updated.isEmpty { return }
        }

        for _ in 0..<Self.maxConflictRetries {
            let current: [[String: AnyJSON]] = try await client.from(table)
                .select("version")
                .eq("household_id", value: op.householdId)
                .eq("id", value: op.entityId)
                .limit(1)
                .execute()
                .value
            guard let currentRow = current.first else {
                return // row gone — treat as done
            }
            let remoteVersion = intValue(SyncJSONBridge.fromAnyObject(currentRow)["version"], default: 0)
            let row = versionedPatch(patch, version: remoteVersion + 1, op: op, clientUpdatedAt: clientUpdatedAt)
            let updated: [[String: AnyJSON]] = try await client.from(table)
                .update(SyncJSONBridge.toAnyObject(row))
                .eq("household_id", value: op.householdId)
                .eq("id", value: op.entityId)
                .eq("version", value: remoteVersion)
                .execute()
                .value
            if !updated.isEmpty { return }
        }
        throw SyncGatewayError.conflictUnresolved(op.entityId)
    }

    /// Stamps a partial patch with the sync columns every write must carry.
    private func versionedPatch(
        _ patch: [String: JSONValue],
        version: Int,
        op: SyncOperation,
        clientUpdatedAt: String
    ) -> [String: JSONValue] {
        var row = patch
        row["version"] = .int(version)
        row["client_id"] = .string(op.clientId)
        row["client_updated_at"] = .string(clientUpdatedAt)
        return row
    }

    // MARK: - Helpers

    /// Mirrors Dart `entityId = isUuid(op.entityId) ? op.entityId : op.patch['id']`,
    /// falling back to the op's own id when the patch carries no string id.
    private func resolvedEntityId(_ op: SyncOperation) -> String {
        if ProposalApply.isUuid(op.entityId) { return op.entityId }
        if case let .string(value) = op.patch["id"] { return value }
        return op.entityId
    }

    /// `(value as num?)?.toInt() ?? default` — the actual remote version, NOT the
    /// upsert-clamped one (a contended write must rebase on the real version).
    private func intValue(_ value: JSONValue?, default fallback: Int) -> Int {
        switch value {
        case let .int(number): return number
        case let .double(number): return Int(number)
        default: return fallback
        }
    }

    private func reportPushError(_ op: SyncOperation, _ error: Error) {
        Self.logger.error(
            "push failed \(op.entityType.rawValue, privacy: .public)/\(op.operation.rawValue, privacy: .public) id=\(op.id, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        diagnostics.failure("sync.push", error: error, [
            "entityType": op.entityType.rawValue,
            "operation": op.operation.rawValue,
        ])
    }

    private func reportConflict(_ op: SyncOperation, fields: [String]) {
        Self.logger.notice(
            "conflict resolved (client wins) \(op.entityType.rawValue, privacy: .public) id=\(op.entityId, privacy: .public) fields=\(fields.joined(separator: ","), privacy: .public)"
        )
        diagnostics.breadcrumb("sync.conflict", [
            "entityType": op.entityType.rawValue,
            "fieldCount": String(fields.count),
        ])
    }
}

// MARK: - Entity codec table

extension SupabaseSyncGateway {
    /// Binds one content entity's `rowForUpsert` + `rowFromJson` so the versioned
    /// write path is entity-agnostic. `@Sendable` (every member is a capture-free
    /// reference to a `RemoteRowCodec` static func) so it can be a `static let`.
    fileprivate struct EntityCodec: Sendable {
        typealias Upsert = @Sendable (String, [String: JSONValue]) -> [String: JSONValue]
        typealias FromJson = @Sendable ([String: JSONValue]) -> [String: JSONValue]
        let rowForUpsert: Upsert
        let rowFromJson: FromJson

        static let inventory = EntityCodec(
            rowForUpsert: { RemoteRowCodec.inventoryRowForUpsert(householdID: $0, item: $1) },
            rowFromJson: { RemoteRowCodec.inventoryRowFromJson($0) }
        )
        static let shopping = EntityCodec(
            rowForUpsert: { RemoteRowCodec.shoppingRowForUpsert(householdID: $0, item: $1) },
            rowFromJson: { RemoteRowCodec.shoppingRowFromJson($0) }
        )
        static let customRecipe = EntityCodec(
            rowForUpsert: { RemoteRowCodec.customRecipeRowForUpsert(householdID: $0, recipe: $1) },
            rowFromJson: { RemoteRowCodec.customRecipeRowFromJson($0) }
        )
        static let mealPlan = EntityCodec(
            rowForUpsert: { RemoteRowCodec.mealPlanEntryRowForUpsert(householdID: $0, entry: $1) },
            rowFromJson: { RemoteRowCodec.mealPlanEntryRowFromJson($0) }
        )
        static let foodLog = EntityCodec(
            rowForUpsert: { RemoteRowCodec.foodLogEntryRowForUpsert(householdID: $0, entry: $1) },
            rowFromJson: { RemoteRowCodec.foodLogEntryRowFromJson($0) }
        )
        static let favoriteRecipe = EntityCodec(
            rowForUpsert: { RemoteRowCodec.favoriteRecipeRowForUpsert(householdID: $0, favorite: $1) },
            rowFromJson: { RemoteRowCodec.favoriteRecipeRowFromJson($0) }
        )
        static let dietaryPreference = EntityCodec(
            rowForUpsert: { RemoteRowCodec.dietaryPreferenceRowForUpsert(householdID: $0, preference: $1) },
            rowFromJson: { RemoteRowCodec.dietaryPreferenceRowFromJson($0) }
        )
    }
}

/// Push-time failures surfaced to the coordinator (which leaves the op in the
/// outbox for the next trigger). Mirrors the Dart `ArgumentError`/`StateError`.
enum SyncGatewayError: Error {
    /// A versioned (non-first) write was attempted for a non-UUID entity id.
    case nonUuidVersionedWrite(String)
    /// A partial-column write (toggle/soft-delete) was attempted for a non-UUID id.
    case nonUuidPartialWrite(String)
    /// The contended-write retry budget was exhausted.
    case conflictUnresolved(String)
}
