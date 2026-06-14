import Foundation

/// Splits a cooking step's text into plain runs and inline ingredient mentions so
/// Cook Mode can render the (scaled) amount right where an ingredient appears
/// ("加入 [番茄 2个] 翻炒") — removing the "这一步放多少" lookup. Pure / testable.
///
/// Matching is LITERAL substring with longest-name-first precedence so "豆腐"
/// wins over "豆", and only ingredients carrying a non-empty amount are annotated
/// (a bare name with no quantity adds nothing over the plain text).
enum StepIngredientAnnotator {
    enum Segment: Equatable {
        case text(String)
        case ingredient(name: String, amount: String)
    }

    static func annotate(_ step: String, ingredients: [RecipeIngredient]) -> [Segment] {
        // (name, amount) for ingredients with a real amount, longest name first.
        let candidates = ingredients
            .map { (name: $0.name.trimmed, amount: $0.fractionAmount.trimmed) }
            .filter { !$0.name.isEmpty && !$0.amount.isEmpty }
            .sorted { $0.name.count > $1.name.count }
        guard !candidates.isEmpty else { return step.isEmpty ? [] : [.text(step)] }

        var segments: [Segment] = []
        var pending = ""
        let chars = Array(step)
        var i = 0
        while i < chars.count {
            var matched: (name: String, amount: String)?
            for candidate in candidates {
                let nameChars = Array(candidate.name)
                if i + nameChars.count <= chars.count,
                   Array(chars[i ..< i + nameChars.count]) == nameChars {
                    matched = candidate
                    break
                }
            }
            if let matched {
                if !pending.isEmpty {
                    segments.append(.text(pending))
                    pending = ""
                }
                segments.append(.ingredient(name: matched.name, amount: matched.amount))
                i += matched.name.count
            } else {
                pending.append(chars[i])
                i += 1
            }
        }
        if !pending.isEmpty { segments.append(.text(pending)) }
        return segments
    }

    /// Whether annotating would change anything (any inline ingredient found) —
    /// lets the view skip the segmented renderer for plain steps.
    static func hasAnnotations(_ step: String, ingredients: [RecipeIngredient]) -> Bool {
        annotate(step, ingredients: ingredients).contains {
            if case .ingredient = $0 { return true }
            return false
        }
    }
}
