import Foundation
import Testing
@testable import FreshPantry

/// `QuantityText.formatFraction` (display-only clean fractions) + the
/// `RecipeIngredient.fractionAmount` derived display string. Storage / shopping
/// details keep using the decimal `formatQuantity` / `displayAmount`.
struct QuantityFractionTests {
    @Test func wholeNumbersStayInts() {
        #expect(QuantityText.formatFraction(2) == "2")
        #expect(QuantityText.formatFraction(0) == "0")
        #expect(QuantityText.formatFraction(10) == "10")
    }

    @Test func commonFractionsRenderGlyphs() {
        #expect(QuantityText.formatFraction(0.5) == "½")
        #expect(QuantityText.formatFraction(0.25) == "¼")
        #expect(QuantityText.formatFraction(0.75) == "¾")
        #expect(QuantityText.formatFraction(0.125) == "⅛")
        #expect(QuantityText.formatFraction(1.0 / 3) == "⅓")
        #expect(QuantityText.formatFraction(2.0 / 3) == "⅔")
        #expect(QuantityText.formatFraction(0.375) == "⅜")
    }

    @Test func mixedNumbersCombineWholeAndGlyph() {
        #expect(QuantityText.formatFraction(1.5) == "1½")
        #expect(QuantityText.formatFraction(2.25) == "2¼")
    }

    @Test func nearbyValuesSnapWithinTolerance() {
        #expect(QuantityText.formatFraction(0.66) == "⅔")
        #expect(QuantityText.formatFraction(0.51) == "½")
    }

    @Test func unfamiliarValuesFallBackToDecimal() {
        // 0.2 (⅕) is intentionally NOT in the cooking table → plain decimal.
        #expect(QuantityText.formatFraction(0.2) == "0.2")
        #expect(QuantityText.formatFraction(1.2) == "1.2")
        #expect(QuantityText.formatFraction(0.1) == "0.1")
    }

    @Test func negativeFallsBackToFormatQuantity() {
        #expect(QuantityText.formatFraction(-1.5) == QuantityText.formatQuantity(-1.5))
    }

    @Test func fractionAmountUsesGlyphsAndKeepsUnit() {
        let half = RecipeIngredient(name: "糖", quantity: 0.5, unit: "杯")
        #expect(half.fractionAmount == "½杯")
        let mixed = RecipeIngredient(name: "面粉", quantity: 1.5, unit: "杯")
        #expect(mixed.fractionAmount == "1½杯")
    }

    @Test func fractionAmountRangeRendersBothBounds() {
        let range = RecipeIngredient(name: "盐", quantity: 0.5, quantityMax: 0.75, unit: "茶匙")
        #expect(range.fractionAmount == "½-¾茶匙")
    }

    @Test func fractionAmountFallsBackToNoteAndUnit() {
        #expect(RecipeIngredient(name: "葱", note: "适量").fractionAmount == "适量")
        #expect(RecipeIngredient(name: "蒜", unit: "瓣").fractionAmount == "瓣")
    }

    @Test func displayAmountStaysDecimalForShoppingMergeability() {
        // displayAmount must remain parseable by parseLeadingQuantity (no glyphs).
        let half = RecipeIngredient(name: "糖", quantity: 0.5, unit: "杯")
        #expect(half.displayAmount == "0.5杯")
        #expect(QuantityText.parseLeadingQuantity(half.displayAmount) != nil)
    }
}
