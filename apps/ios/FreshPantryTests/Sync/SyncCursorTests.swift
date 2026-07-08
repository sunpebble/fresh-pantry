import Foundation
import Supabase
import Testing
@testable import FreshPantry

/// Pins the inbound-watermark chain on DECODED rows. The codecs drop the
/// unmapped `updated_at` wire column, so `RemotePantryRepository.decodeRow`
/// re-stamps it via `SyncCursor.stampUpdatedAt` — without the stamp the cursor
/// never advances and `refreshDelta`'s incremental pull is a permanent no-op.
struct SyncCursorTests {
    private static let uuid = "11111111-2222-4333-8444-555555555555"
    private static let iso = "2026-07-01T08:30:00.000Z"
    private static let laterIso = "2026-07-02T09:00:00.000Z"

    private static let rawInventoryRow: [String: JSONValue] = [
        "id": .string(uuid),
        "name": .string("牛奶"),
        "updated_at": .string(iso),
    ]

    @Test func decodedRowAloneCannotAdvanceCursor() {
        // The regression this file pins: codec output carries no `updated_at`.
        let decoded = RemoteRowCodec.inventoryRowFromJson(Self.rawInventoryRow)
        #expect(SyncCursor.advance(nil, with: [decoded]) == nil)
    }

    @Test func stampedColumnTableRowAdvancesCursor() throws {
        let raw = Self.rawInventoryRow
        let stamped = SyncCursor.stampUpdatedAt(RemoteRowCodec.inventoryRowFromJson(raw), from: raw)
        let expected = try #require(JSONDate.parse(Self.iso))
        #expect(SyncCursor.advance(nil, with: [stamped]) == expected)
    }

    @Test func stampedPayloadRowAdvancesCursor() throws {
        // The other decode shape: payload-blob entities (recipes, meal plan, …).
        let raw: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "payload": .object(["id": .string(Self.uuid)]),
            "updated_at": .string(Self.iso),
        ]
        let stamped = SyncCursor.stampUpdatedAt(RemoteRowCodec.customRecipeRowFromJson(raw), from: raw)
        let expected = try #require(JSONDate.parse(Self.iso))
        #expect(SyncCursor.advance(nil, with: [stamped]) == expected)
    }

    /// Pins the actual `loadRows` per-row transform (bridge → decode → stamp),
    /// not just the stamp helper — reverting the wiring in the repository
    /// would fail here even with `stampUpdatedAt` still present.
    @Test func decodeRowStampsUpdatedAtFromWireRow() throws {
        let anyRow: [String: AnyJSON] = [
            "id": .string(Self.uuid),
            "name": .string("牛奶"),
            "updated_at": .string(Self.iso),
        ]
        let domain = RemotePantryRepository.decodeRow(anyRow, decode: RemoteRowCodec.inventoryRowFromJson)
        #expect(domain["name"] == .string("牛奶"))
        let expected = try #require(JSONDate.parse(Self.iso))
        #expect(SyncCursor.advance(nil, with: [domain]) == expected)
    }

    @Test func decodeRowWithoutUpdatedAtStampsNullAndKeepsCursor() throws {
        let anyRow: [String: AnyJSON] = ["id": .string(Self.uuid), "name": .string("牛奶")]
        let domain = RemotePantryRepository.decodeRow(anyRow, decode: RemoteRowCodec.inventoryRowFromJson)
        #expect(domain["updated_at"] == .null)
        let cursor = try #require(JSONDate.parse(Self.iso))
        #expect(SyncCursor.advance(cursor, with: [domain]) == cursor)
    }

    @Test func advanceTakesMaxAndNeverRegresses() throws {
        let raw = Self.rawInventoryRow
        let stamped = SyncCursor.stampUpdatedAt(RemoteRowCodec.inventoryRowFromJson(raw), from: raw)
        let rowDate = try #require(JSONDate.parse(Self.iso))
        // Cursor already ahead of every row → unchanged.
        let later = try #require(JSONDate.parse(Self.laterIso))
        #expect(SyncCursor.advance(later, with: [stamped]) == later)
        // Cursor behind → advances to the row's timestamp.
        let earlier = try #require(JSONDate.parse("2026-06-30T00:00:00.000Z"))
        #expect(SyncCursor.advance(earlier, with: [stamped]) == rowDate)
    }

    @Test func advanceWithoutTimestampsKeepsCursor() throws {
        let cursor = try #require(JSONDate.parse(Self.iso))
        #expect(SyncCursor.advance(cursor, with: [["id": .string(Self.uuid)]]) == cursor)
        #expect(SyncCursor.advance(cursor, with: []) == cursor)
    }
}
