import Foundation
import Testing
@testable import FreshPantry

/// Pure `SeasonalRules` — solar term resolution + in-season recipe ranking (#11).
struct SeasonalRulesTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func recipe(_ name: String, _ ingredients: [String]) -> Recipe {
        Recipe(
            id: name, name: name, category: "荤菜", difficulty: 1, cookingMinutes: 10,
            description: "", ingredients: ingredients.map { RecipeIngredient(name: $0) },
            steps: [], tags: []
        )
    }

    @Test func currentTermPicksLastStartedTerm() {
        #expect(SeasonalRules.currentTerm(date(6, 10), calendar: cal).name == "芒种") // 芒种 6/5
        #expect(SeasonalRules.currentTerm(date(6, 5), calendar: cal).name == "芒种") // exact start
        #expect(SeasonalRules.currentTerm(date(6, 4), calendar: cal).name == "小满") // before 芒种
    }

    @Test func earlyJanuaryWrapsToWinterSolstice() {
        #expect(SeasonalRules.currentTerm(date(1, 3), calendar: cal).name == "冬至")
    }

    @Test func seasonByMonth() {
        #expect(SeasonalRules.season(date(4, 1), calendar: cal) == .spring)
        #expect(SeasonalRules.season(date(7, 1), calendar: cal) == .summer)
        #expect(SeasonalRules.season(date(10, 1), calendar: cal) == .autumn)
        #expect(SeasonalRules.season(date(1, 1), calendar: cal) == .winter)
    }

    @Test func seasonalKeywordsMatchSeason() {
        #expect(SeasonalRules.seasonalKeywords(date(4, 1), calendar: cal).contains("春笋"))
        #expect(SeasonalRules.seasonalKeywords(date(7, 1), calendar: cal).contains("黄瓜"))
    }

    @Test func scoreCountsDistinctSeasonalIngredients() {
        let summerKeywords = SeasonalRules.seasonalIngredients[.summer]!
        let r = recipe("凉拌", ["黄瓜", "番茄", "盐"])
        #expect(SeasonalRules.seasonalScore(r, keywords: summerKeywords) == 2)
    }

    @Test func rankRecipesOrdersBySeasonalMatchDescAndFilters() {
        let recipes = [
            recipe("红烧肉", ["五花肉", "酱油"]), // 0 seasonal
            recipe("拍黄瓜", ["黄瓜", "蒜"]), // 1
            recipe("夏日杂蔬", ["黄瓜", "茄子", "苦瓜"]), // 3
        ]
        let ranked = SeasonalRules.rankRecipes(recipes, date: date(7, 1), calendar: cal)
        #expect(ranked.map(\.name) == ["夏日杂蔬", "拍黄瓜"]) // 红烧肉 filtered out
    }

    @Test func rankRecipesRespectsLimit() {
        let recipes = (0..<10).map { recipe("黄瓜菜\($0)", ["黄瓜"]) }
        #expect(SeasonalRules.rankRecipes(recipes, date: date(7, 1), calendar: cal, limit: 3).count == 3)
    }
}
