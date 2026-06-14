import Foundation
import Testing
@testable import FreshPantry

/// `NutritionFacts.fromOffProduct` — macros + product-level OFF grades
/// (Nutri-Score / NOVA / Eco-Score / additives) for the scan badge row.
struct NutritionGradesTests {
    @Test func parsesGradesAndMacros() {
        let facts = NutritionFacts.fromOffProduct([
            "nutriments": ["energy-kcal_100g": 250, "proteins_100g": 8.0],
            "nutriscore_grade": "a",
            "nova_group": 4,
            "ecoscore_grade": "C",
            "additives_tags": ["en:e100", "en:e200"],
        ])
        #expect(facts?.nutriScore == "a")
        #expect(facts?.novaGroup == 4)
        #expect(facts?.ecoScore == "c") // normalized lowercase
        #expect(facts?.additivesCount == 2)
        #expect(facts?.energyKcal == 250)
        #expect(facts?.protein == 8.0)
        #expect(facts?.hasGrades == true)
    }

    @Test func gradesOnlyProductStillBuilds() {
        let facts = NutritionFacts.fromOffProduct(["nutriscore_grade": "b"])
        #expect(facts != nil)
        #expect(facts?.nutriScore == "b")
        #expect(facts?.energyKcal == nil)
        #expect(facts?.hasGrades == true)
    }

    @Test func unknownGradeIsDropped() {
        let facts = NutritionFacts.fromOffProduct([
            "nutriments": ["energy-kcal_100g": 100],
            "nutriscore_grade": "unknown",
            "ecoscore_grade": "not-applicable",
        ])
        #expect(facts?.nutriScore == nil)
        #expect(facts?.ecoScore == nil)
        #expect(facts?.hasGrades == false)
    }

    @Test func novaAcceptsStringAndRejectsOutOfRange() {
        #expect(NutritionFacts.fromOffProduct(["nova_group": "3"])?.novaGroup == 3)
        #expect(NutritionFacts.fromOffProduct(["nova_group": 5])?.novaGroup == nil)
        #expect(NutritionFacts.fromOffProduct(["nova_group": 0])?.novaGroup == nil)
    }

    @Test func emptyAdditivesIsNil() {
        let facts = NutritionFacts.fromOffProduct([
            "nutriments": ["proteins_100g": 5.0],
            "additives_tags": [String](),
        ])
        #expect(facts?.additivesCount == nil)
    }

    @Test func emptyProductIsNil() {
        #expect(NutritionFacts.fromOffProduct([:]) == nil)
    }

    @Test func gradesSurviveCodableRoundTrip() throws {
        let facts = NutritionFacts(energyKcal: 100, nutriScore: "d", novaGroup: 4, ecoScore: "e", additivesCount: 3)
        let data = try JSONEncoder().encode(facts)
        let decoded = try JSONDecoder().decode(NutritionFacts.self, from: data)
        #expect(decoded == facts)
    }

    @Test func gradeColorSeverity() {
        #expect(NutritionCard.gradeColor("a") == .fkSuccess)
        #expect(NutritionCard.gradeColor("c") == .fkWarn)
        #expect(NutritionCard.gradeColor("e") == .fkDanger)
        #expect(NutritionCard.novaColor(1) == .fkSuccess)
        #expect(NutritionCard.novaColor(4) == .fkDanger)
    }
}
