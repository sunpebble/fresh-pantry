import Foundation

/// One dish in a reusable weekly meal-plan template, stored by RELATIVE day
/// offset (0 = the week's Monday … 6 = Sunday) so it can be re-applied to any week.
struct MealPlanTemplateItem: Codable, Equatable, Sendable {
    var recipeId: String
    var recipeName: String
    var recipeImageUrl: String?
    var dayOffset: Int
    var servings: Int
}

/// A named, reusable week of meals (#14). Device-local — a personal planning
/// shortcut, not household-shared (to start).
struct MealPlanTemplate: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var items: [MealPlanTemplateItem]
}

/// Pure builder + device-local persistence for meal-plan templates. The builder
/// is unit-testable; persistence is a thin UserDefaults(JSON) wrapper.
enum MealPlanTemplates {
    static let storageKey = "meal_plan_templates"

    private static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Builds template items from a week's entries: each entry's `dayOffset` is its
    /// day distance from `weekStart`. Entries outside 0...6, or note-only rows
    /// (empty recipeId), are dropped.
    static func items(from entries: [MealPlanEntry], weekStart: Date) -> [MealPlanTemplateItem] {
        let cal = calendar()
        let start = MealPlanEntry.dateOnly(weekStart)
        return entries.compactMap { entry in
            guard !entry.recipeId.isEmpty else { return nil }
            let offset = cal.dateComponents([.day], from: start, to: MealPlanEntry.dateOnly(entry.date)).day ?? -1
            guard (0...6).contains(offset) else { return nil }
            return MealPlanTemplateItem(
                recipeId: entry.recipeId,
                recipeName: entry.recipeName,
                recipeImageUrl: entry.recipeImageUrl,
                dayOffset: offset,
                servings: entry.servings
            )
        }
    }

    // MARK: Persistence

    static func load(_ defaults: UserDefaults = .standard) -> [MealPlanTemplate] {
        guard let data = defaults.data(forKey: storageKey),
              let templates = try? JSONDecoder().decode([MealPlanTemplate].self, from: data)
        else { return [] }
        return templates
    }

    static func save(_ templates: [MealPlanTemplate], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Adds (or replaces by case-insensitive name) a template and returns the new
    /// list — newest first, so "应用模板" surfaces the most recent at the top.
    static func upserting(_ template: MealPlanTemplate, into list: [MealPlanTemplate]) -> [MealPlanTemplate] {
        let key = template.name.trimmed.lowercased()
        var result = list.filter { $0.name.trimmed.lowercased() != key }
        result.insert(template, at: 0)
        return result
    }
}
