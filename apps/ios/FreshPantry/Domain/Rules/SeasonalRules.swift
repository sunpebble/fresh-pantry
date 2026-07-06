import Foundation

/// 二十四节气 + 应季食材 driven seasonal recommendations — a culturally native
/// "今天该吃什么" hook for Chinese users that needs no active search. Pure /
/// testable: maps a date to its current solar term and ranks recipes by how many
/// in-season ingredients they use.
enum SeasonalRules {
    struct SolarTerm: Equatable, Sendable {
        let name: String
        let month: Int
        let day: Int // typical start day (±1 across years; fine for recommendation)
    }

    enum Season: String, Sendable, CaseIterable {
        case spring = "春", summer = "夏", autumn = "秋", winter = "冬" // i18n:ignore domain matching data, not UI text
    }

    /// The 24 terms in calendar order (小寒 ~Jan 5 … 冬至 ~Dec 22).
    static let terms: [SolarTerm] = [
        .init(name: "小寒", month: 1, day: 5), .init(name: "大寒", month: 1, day: 20), // i18n:ignore domain matching data, not UI text
        .init(name: "立春", month: 2, day: 4), .init(name: "雨水", month: 2, day: 19), // i18n:ignore domain matching data, not UI text
        .init(name: "惊蛰", month: 3, day: 5), .init(name: "春分", month: 3, day: 20), // i18n:ignore domain matching data, not UI text
        .init(name: "清明", month: 4, day: 4), .init(name: "谷雨", month: 4, day: 20), // i18n:ignore domain matching data, not UI text
        .init(name: "立夏", month: 5, day: 5), .init(name: "小满", month: 5, day: 21), // i18n:ignore domain matching data, not UI text
        .init(name: "芒种", month: 6, day: 5), .init(name: "夏至", month: 6, day: 21), // i18n:ignore domain matching data, not UI text
        .init(name: "小暑", month: 7, day: 7), .init(name: "大暑", month: 7, day: 22), // i18n:ignore domain matching data, not UI text
        .init(name: "立秋", month: 8, day: 7), .init(name: "处暑", month: 8, day: 23), // i18n:ignore domain matching data, not UI text
        .init(name: "白露", month: 9, day: 7), .init(name: "秋分", month: 9, day: 23), // i18n:ignore domain matching data, not UI text
        .init(name: "寒露", month: 10, day: 8), .init(name: "霜降", month: 10, day: 23), // i18n:ignore domain matching data, not UI text
        .init(name: "立冬", month: 11, day: 7), .init(name: "小雪", month: 11, day: 22), // i18n:ignore domain matching data, not UI text
        .init(name: "大雪", month: 12, day: 7), .init(name: "冬至", month: 12, day: 22), // i18n:ignore domain matching data, not UI text
    ]

    /// In-season ingredient keywords per season (substring matched against recipe
    /// ingredient names / title / tags).
    static let seasonalIngredients: [Season: [String]] = [
        .spring: ["春笋", "韭菜", "菠菜", "豌豆", "荠菜", "香椿", "草莓", "芦笋", "蚕豆", "莴笋"], // i18n:ignore domain matching data, not UI text
        .summer: ["黄瓜", "西瓜", "冬瓜", "丝瓜", "苦瓜", "茄子", "番茄", "绿豆", "豆角", "毛豆"], // i18n:ignore domain matching data, not UI text
        .autumn: ["莲藕", "南瓜", "板栗", "山药", "柚子", "梨", "螃蟹", "芋头", "菱角", "红薯"], // i18n:ignore domain matching data, not UI text
        .winter: ["白萝卜", "大白菜", "羊肉", "冬笋", "橘子", "白菜", "萝卜", "山楂", "韭黄", "菜花"], // i18n:ignore domain matching data, not UI text
    ]

    /// The solar term in effect on `date` — the last term whose start ≤ date
    /// (wrapping: dates before 小寒 belong to the prior year's 冬至).
    static func currentTerm(_ date: Date, calendar: Calendar = .current) -> SolarTerm {
        let comps = calendar.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let ordinal = month * 100 + day
        var current = terms.last! // 冬至 wrap for early-January dates
        for term in terms where term.month * 100 + term.day <= ordinal {
            current = term
        }
        return current
    }

    /// Season for a date (by month: 3–5 春, 6–8 夏, 9–11 秋, 12/1/2 冬).
    static func season(_ date: Date, calendar: Calendar = .current) -> Season {
        switch calendar.dateComponents([.month], from: date).month ?? 1 {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }

    /// In-season keywords for the date's season.
    static func seasonalKeywords(_ date: Date, calendar: Calendar = .current) -> [String] {
        seasonalIngredients[season(date, calendar: calendar)] ?? []
    }

    /// Display-only localized season name for the seasonal carousel header.
    static func localizedSeasonName(_ season: Season) -> String {
        let key: String
        switch season {
        case .spring: key = "season.spring"
        case .summer: key = "season.summer"
        case .autumn: key = "season.autumn"
        case .winter: key = "season.winter"
        }
        return String(localized: String.LocalizationValue(key))
    }

    /// How many distinct in-season keywords a recipe touches (ingredients/name/tags).
    static func seasonalScore(_ recipe: Recipe, keywords: [String]) -> Int {
        guard !keywords.isEmpty else { return 0 }
        let haystacks = recipe.ingredients.map { $0.name } + [recipe.name] + recipe.tags
        let blob = haystacks.joined(separator: " ")
        return keywords.filter { blob.contains($0) }.count
    }

    /// Recipes that use ≥1 in-season ingredient, ranked by distinct in-season
    /// matches (desc); ties keep input order. Capped at `limit`.
    static func rankRecipes(
        _ recipes: [Recipe],
        date: Date,
        calendar: Calendar = .current,
        limit: Int = 6
    ) -> [Recipe] {
        let keywords = seasonalKeywords(date, calendar: calendar)
        guard !keywords.isEmpty else { return [] }
        let scored = recipes.enumerated()
            .map { (offset: $0.offset, recipe: $0.element, score: seasonalScore($0.element, keywords: keywords)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.offset < rhs.offset
            }
        return Array(scored.prefix(limit).map(\.recipe))
    }
}
