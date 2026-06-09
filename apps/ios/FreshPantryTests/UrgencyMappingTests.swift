import Testing
@testable import FreshPantry

/// Parity for the single urgency-color source: `FreshnessState` → `FkStatus` →
/// `FkStatusStyle` labels. Guards against any view re-deriving these.
struct UrgencyMappingTests {
    @Test func freshnessStateMapsToExpectedStatus() {
        #expect(FreshnessState.fresh.fkStatus == .fresh)
        #expect(FreshnessState.expiringSoon.fkStatus == .soon)
        #expect(FreshnessState.urgent.fkStatus == .urgent)
        #expect(FreshnessState.expired.fkStatus == .expired)
    }

    @Test func statusStyleLabelsMatchSpec() {
        #expect(FreshnessState.fresh.statusStyle.label == "新鲜")
        #expect(FreshnessState.expiringSoon.statusStyle.label == "即将过期")
        #expect(FreshnessState.urgent.statusStyle.label == "快过期")
        #expect(FreshnessState.expired.statusStyle.label == "已过期")
    }

    @Test func lowIsTheExtraNonDomainStatus() {
        // FkStatus adds `low` for shopping / low-stock; not reachable from any
        // FreshnessState.
        #expect(FkStatusStyle.of(.low).label == "库存不足")
        let domainStatuses = FreshnessState.allCases.map(\.fkStatus)
        #expect(!domainStatuses.contains(.low))
    }

    @Test func categoryPaletteIdMappingMatchesFlutter() {
        #expect(FkCategoryIcon.paletteId(for: FoodCategories.dairyAndEggs) == "dairy")
        #expect(FkCategoryIcon.paletteId(for: FoodCategories.freshProduce) == "veg")
        #expect(FkCategoryIcon.paletteId(for: FoodCategories.meatAndSeafood) == "meat")
        #expect(FkCategoryIcon.paletteId(for: FoodCategories.herbsAndSpices) == "sauce")
        #expect(FkCategoryIcon.paletteId(for: FoodCategories.other) == "grain")
        #expect(FkCategoryIcon.paletteId(for: nil) == "grain") // default fallback
    }
}
