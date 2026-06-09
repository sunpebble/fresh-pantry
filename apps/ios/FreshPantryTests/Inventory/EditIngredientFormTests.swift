import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for `EditIngredientForm`: seeding from the original row, the
/// shelf-life → expiry recompute, validation, and provenance-preserving build.
@MainActor
struct EditIngredientFormTests {
    private func makeItem(
        id: String = "a",
        name: String = "牛奶",
        quantity: String = "2",
        unit: String = "盒",
        category: String? = FoodCategories.dairyAndEggs,
        storage: IconType = .fridge,
        expiryDate: Date? = nil,
        addedAt: Date? = nil,
        shelfLifeDays: Int? = nil,
        barcode: String? = nil,
        imageUrl: String = "",
        remoteVersion: Int = 0
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, quantity: quantity, unit: unit, imageUrl: imageUrl,
            freshnessPercent: 1.0, state: .fresh, category: category, barcode: barcode,
            storage: storage, expiryDate: expiryDate, addedAt: addedAt,
            shelfLifeDays: shelfLifeDays, remoteVersion: remoteVersion
        )
    }

    // MARK: Seeding

    @Test func seedsEditableFieldsFromOriginal() {
        let expiry = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let form = EditIngredientForm(makeItem(
            storage: .pantry, expiryDate: expiry, shelfLifeDays: 7
        ))
        #expect(form.name == "牛奶")
        #expect(form.quantity == "2")
        #expect(form.unit == "盒")
        #expect(form.category == FoodCategories.dropdownValue(FoodCategories.dairyAndEggs))
        #expect(form.storage == .pantry)
        #expect(form.shelfLifeDays == 7)
        #expect(form.expiryDate == expiry)
    }

    @Test func seedDerivesShelfLifeFromExpiryWhenUnsaved() {
        // No saved shelfLifeDays, but an expiry 5 days out ⇒ seed shelf-life = 5.
        let today = Calendar.current.startOfDay(for: Date())
        let expiry = Calendar.current.date(byAdding: .day, value: 5, to: today)!
        let form = EditIngredientForm(makeItem(expiryDate: expiry, shelfLifeDays: nil))
        #expect(form.shelfLifeDays == 5)
        #expect(form.expiryDate == expiry)
    }

    @Test func seedNoExpiryLeavesShelfLifeNil() {
        let form = EditIngredientForm(makeItem(expiryDate: nil, shelfLifeDays: nil))
        #expect(form.shelfLifeDays == nil)
        #expect(form.expiryDate == nil)
    }

    @Test func blankUnitSeedsDefault() {
        let form = EditIngredientForm(makeItem(unit: ""))
        #expect(form.unit == "个")
    }

    // MARK: Shelf-life → expiry recompute

    @Test func setShelfLifeRecomputesExpiryToTodayPlusDays() throws {
        let now = Date()
        let form = EditIngredientForm(makeItem())
        form.setShelfLife(3, now: now)
        #expect(form.shelfLifeDays == 3)
        let expiry = try #require(form.expiryDate)
        #expect(ExpiryCalculator.daysUntilExpiry(expiry, now: now) == 3)
    }

    @Test func setShelfLifeNilClearsExpiry() {
        let expiry = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let form = EditIngredientForm(makeItem(expiryDate: expiry, shelfLifeDays: 7))
        form.setShelfLife(nil)
        #expect(form.shelfLifeDays == nil)
        #expect(form.expiryDate == nil)
    }

    @Test func setShelfLifeNonPositiveClearsExpiry() {
        let form = EditIngredientForm(makeItem())
        form.setShelfLife(0)
        #expect(form.shelfLifeDays == nil)
        #expect(form.expiryDate == nil)
    }

    // MARK: Validation

    @Test func canSubmitRequiresNameAndPositiveQuantity() {
        let form = EditIngredientForm(makeItem())
        #expect(form.canSubmit)

        form.name = "   "
        #expect(!form.canSubmit)

        form.name = "牛奶"
        form.quantity = "0"
        #expect(!form.canSubmit)
        form.quantity = "-1"
        #expect(!form.canSubmit)
        form.quantity = "."
        #expect(!form.canSubmit)
        form.quantity = ""
        #expect(form.canSubmit) // blank ⇒ defaults to 1
        form.quantity = "2.5"
        #expect(form.canSubmit)
    }

    // MARK: Build

    @Test func buildEditedPreservesProvenanceAndCarriesNewFields() {
        let addedAt = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let form = EditIngredientForm(makeItem(
            addedAt: addedAt, barcode: "690123", imageUrl: "img://x", remoteVersion: 9
        ))
        form.name = "酸奶"
        form.quantity = "3"
        form.setUnit("瓶")
        form.setStorage(.pantry)

        let edited = form.buildEdited()
        #expect(edited.id == "a")
        #expect(edited.name == "酸奶")
        #expect(edited.quantity == "3")
        #expect(edited.unit == "瓶")
        #expect(edited.storage == .pantry)
        #expect(edited.addedAt == addedAt) // preserved
        #expect(edited.barcode == "690123") // preserved
        #expect(edited.imageUrl == "img://x") // preserved
        #expect(edited.remoteVersion == 9) // preserved (baseVersion source)
    }

    @Test func buildEditedBlankQuantityDefaultsToOne() {
        let form = EditIngredientForm(makeItem(quantity: "5"))
        form.quantity = "   "
        #expect(form.buildEdited().quantity == "1")
    }
}
