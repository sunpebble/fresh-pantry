import Testing
@testable import FreshPantry

struct FreeTierTests {
    @Test func proNeverBlocked() {
        #expect(FreeTier.inventoryLimitReached(isPro: true, currentCount: 999) == false)
    }

    @Test func freeUnderLimitAllowed() {
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 49) == false)
    }

    @Test func freeAtLimitBlocked() {
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 50) == true)
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 51) == true)
    }
}
