import Foundation

/// Holds a recipe URL handed in by the Share Extension via the custom scheme
/// `com.sunpebble.freshpantry://import-recipe?url=…`, until the Recipes tab can open
/// 新建食谱 pre-filled for AI import (parity with the Flutter share intent).
///
/// A single instance lives on `AppDependencies` and is injected into the
/// environment so `onOpenURL` (producer) and `RecipesView` (consumer) share it.
@Observable
@MainActor
final class RecipeImportRouter {
    /// The captured recipe URL awaiting the import form; nil when none pending.
    private(set) var pendingURL: String?

    /// Captures `url` IF it is the import-recipe deep link, returning whether it
    /// matched (so `onOpenURL` can short-circuit). The recipe URL travels in the
    /// `url` query item.
    @discardableResult
    func capture(url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "import-recipe",
              let recipe = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !recipe.trimmed.isEmpty
        else {
            return false
        }
        pendingURL = recipe
        return true
    }

    func clear() { pendingURL = nil }
}
