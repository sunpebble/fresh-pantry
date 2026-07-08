import Foundation
import SwiftData

/// Append-only food-departure log. The four mutation paths are kept DISTINCT
/// (never collapse `deleteEntry` into `saveEntries`). Mirrors
/// `lib/storage/food_log_repo.dart`.
@ModelActor
actor FoodLogRepository {
    /// Append a single entry. NO-OP if id is blank (never write an
    /// unaddressable row). Upserts by id.
    func append(_ householdID: String, _ entry: FoodLogEntry) throws {
        guard !entry.id.isEmpty else { return }
        let id = entry.id
        let existing = try modelContext.fetch(
            FetchDescriptor<FoodLogRecord>(predicate: #Predicate { $0.id == id })
        )
        if let row = existing.first {
            row.householdID = householdID
            row.apply(entry)
        } else {
            modelContext.insert(FoodLogRecord(householdID: householdID, entry: entry))
        }
        try modelContext.save()
    }

    func loadAllFor(_ householdID: String) throws -> [FoodLogEntry] {
        let descriptor = FetchDescriptor<FoodLogRecord>(
            predicate: #Predicate { $0.householdID == householdID }
        )
        return try decode(modelContext.fetch(descriptor))
    }

    /// Bounded recent-window load (avoids scanning unbounded history).
    func loadRecentFor(_ householdID: String, sinceMs: Int) throws -> [FoodLogEntry] {
        let since = Date(timeIntervalSince1970: Double(sinceMs) / 1000)
        let descriptor = FetchDescriptor<FoodLogRecord>(
            predicate: #Predicate { row in
                row.householdID == householdID
                    && (row.loggedAt.flatMap { $0 >= since } ?? false)
            }
        )
        return try decode(modelContext.fetch(descriptor))
    }

    /// Point-update: corrects a single departure's outcome without touching the
    /// bounded history outside this row. Must NOT use `saveEntries`.
    func updateOutcome(_ householdID: String, _ id: String, _ outcome: FoodLogOutcome) throws -> FoodLogEntry? {
        let existing = try modelContext.fetch(
            FetchDescriptor<FoodLogRecord>(predicate: #Predicate {
                $0.householdID == householdID && $0.id == id
            })
        )
        guard let row = existing.first, var entry = try? row.entry() else { return nil }
        guard entry.outcome != outcome else { return entry }
        entry = entry.copyWith(outcome: outcome, clientUpdatedAt: Date())
        row.apply(entry)
        try modelContext.save()
        return entry
    }

    /// CRITICAL point-delete: reverses a single logged row when a removal is
    /// undone. Must NOT use `saveEntries` (which would drop window-outside history).
    func deleteEntry(_ householdID: String, _ id: String) throws {
        try modelContext.delete(
            model: FoodLogRecord.self,
            where: #Predicate { $0.householdID == householdID && $0.id == id }
        )
        try modelContext.save()
    }

    func deleteHouseholdScope(_ householdID: String) throws {
        try modelContext.delete(
            model: FoodLogRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        try modelContext.save()
    }

    /// Sync apply / backup import: replace-all-in-scope of non-blank-id entries.
    func saveEntries(_ householdID: String, _ entries: [FoodLogEntry]) throws {
        try modelContext.delete(
            model: FoodLogRecord.self,
            where: #Predicate { $0.householdID == householdID }
        )
        var seenIds = Set<String>()
        for entry in entries {
            guard !entry.id.isEmpty else { continue }
            if seenIds.contains(entry.id) { continue }
            seenIds.insert(entry.id)
            modelContext.insert(FoodLogRecord(householdID: householdID, entry: entry))
        }
        try modelContext.save()
    }

    /// Atomic load→transform→save in one actor call — the concurrent-write-safe
    /// sync write path (see `InventoryRepository.mutateItems`).
    func mutateEntries(_ householdID: String, _ transform: @Sendable ([FoodLogEntry]) -> [FoodLogEntry]) throws {
        try saveEntries(householdID, transform(loadAllFor(householdID)))
    }

    /// One-shot, idempotent: rewrites legacy `fl_<ms>` ids to lowercase UUIDs so
    /// the row can land in the Supabase `uuid` PK column. Re-encodes the payload's
    /// own `id` too. No-op for rows already on a UUID id. Returns the rewrite count.
    /// Safe because FoodLog is append-only with no foreign references to its id.
    @discardableResult
    func migrateLegacyIds() throws -> Int {
        let legacy = try modelContext.fetch(
            FetchDescriptor<FoodLogRecord>(predicate: #Predicate { $0.id.starts(with: "fl_") })
        )
        var rewritten = 0
        for row in legacy {
            guard let entry = try? row.entry() else { continue }
            let migrated = entry.copyWith(id: FoodLogEntry.newId())
            modelContext.insert(FoodLogRecord(householdID: row.householdID, entry: migrated))
            modelContext.delete(row)
            rewritten += 1
        }
        if rewritten > 0 { try modelContext.save() }
        return rewritten
    }

    private func decode(_ rows: [FoodLogRecord]) -> [FoodLogEntry] {
        rows.compactMap { row -> FoodLogEntry? in
            guard let entry = try? row.entry(), !entry.id.isEmpty else { return nil }
            return entry
        }
    }
}
