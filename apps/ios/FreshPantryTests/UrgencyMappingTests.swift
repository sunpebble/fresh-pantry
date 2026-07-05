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
        #expect(FreshnessState.fresh.statusStyle.label == String(localized: "component.status.fresh"))
        #expect(FreshnessState.expiringSoon.statusStyle.label == String(localized: "component.status.soon"))
        #expect(FreshnessState.urgent.statusStyle.label == String(localized: "component.status.urgent"))
        #expect(FreshnessState.expired.statusStyle.label == String(localized: "component.status.expired"))
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
