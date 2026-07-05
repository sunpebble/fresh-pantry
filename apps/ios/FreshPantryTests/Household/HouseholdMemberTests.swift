import Foundation
import Testing
@testable import FreshPantry

struct HouseholdMemberTests {
    @Test func decodesProfileFieldsFromRPCRow() throws {
        let json = """
        {"household_id":"h1","user_id":"u1","role":"owner","email":"a@b.com",
         "display_name":"小明","nickname":"明明","avatar_path":"u1/x.jpg"}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(HouseholdMember.self, from: json)
        #expect(m.displayName == "小明")
        #expect(m.nickname == "明明")
        #expect(m.avatarPath == "u1/x.jpg")
    }

    @Test func resolvedNamePrefersNicknameThenDisplayNameThenEmail() {
        #expect(HouseholdMember(email: "a@b.com", displayName: "小明", nickname: "明明").resolvedName == "明明")
        #expect(HouseholdMember(email: "a@b.com", displayName: "小明").resolvedName == "小明")
        #expect(HouseholdMember(email: "a@b.com").resolvedName == "a@b.com")
        #expect(HouseholdMember().resolvedName == String(localized: "household.member.fallback"))
    }
}
