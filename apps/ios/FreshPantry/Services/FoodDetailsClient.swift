import Foundation

/// Food-details lookup backed by `OpenFoodFactsService` — barcode-first, then
/// name search. `Sendable` so it can cross the actor / store boundary; stateless.
/// The OFF service is best-effort (errors → nil internally), so `lookup` never
/// throws in practice but keeps `throws` for an alternate backend.
struct OpenFoodFactsDetailsClient: Sendable {
    func lookup(_ ingredient: Ingredient) async throws -> FoodDetails? {
        await OpenFoodFactsService.lookupDetails(
            name: ingredient.name,
            barcode: ingredient.barcode
        )
    }
}
