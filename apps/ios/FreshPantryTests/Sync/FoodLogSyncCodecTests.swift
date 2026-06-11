import Foundation
import Testing
@testable import FreshPantry

/// FoodLog payload-blob codec round-trips a domain entry through the Supabase
/// row shape without field loss (mirrors the meal-plan codec contract).
struct FoodLogSyncCodecTests {
    @Test func payloadRoundTripPreservesFields() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = FoodLogEntry(
            id: "11111111-1111-4111-8111-111111111111",
            name: "牛奶", category: "乳品蛋类", outcome: .wasted,
            loggedAt: t, wasExpiring: true, remoteVersion: 0
        )
        let domain = try #require(DomainJSON.valueMap(entry))
        let row = RemoteRowCodec.foodLogEntryRowForUpsert(householdID: "home", entry: domain)

        // household + payload + sync columns lifted out
        #expect(row["household_id"] == .string("home"))
        #expect(row["version"] == .int(1)) // remoteVersion 0 → first write version 1
        guard case .object = row["payload"] else { Issue.record("payload not object"); return }

        // simulate the Supabase row coming back, then decode to domain
        var back = row
        back["id"] = .string(entry.id) // server echoes the uuid PK column
        let decodedMap = RemoteRowCodec.foodLogEntryRowFromJson(back)
        let decoded = try #require(DomainJSON.fromValueMap(FoodLogEntry.self, from: decodedMap))
        #expect(decoded.id == entry.id)
        #expect(decoded.name == "牛奶")
        #expect(decoded.category == "乳品蛋类")
        #expect(decoded.outcome == .wasted)
        #expect(decoded.loggedAt == t)
        #expect(decoded.wasExpiring == true)
    }
}
