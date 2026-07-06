import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os

/// Typed identity of one Spotlight entry — the bridge between indexing (build
/// the `uniqueIdentifier`) and deep-linking (parse a tapped result back to a
/// model id). Keeping both directions on one type guarantees they can't drift.
enum SpotlightItemID: Hashable, Sendable {
    case ingredient(String)
    case recipe(String)

    private static let ingredientPrefix = "ingredient:"
    private static let recipePrefix = "recipe:"

    /// The `CSSearchableItem.uniqueIdentifier` form: "ingredient:{id}" / "recipe:{id}".
    var identifier: String {
        switch self {
        case .ingredient(let id): return Self.ingredientPrefix + id
        case .recipe(let id): return Self.recipePrefix + id
        }
    }

    /// Parses a tapped result's identifier. nil for an unknown prefix or an
    /// empty payload — a malformed entry must not route anywhere.
    init?(identifier: String) {
        if let id = Self.payload(of: identifier, prefix: Self.ingredientPrefix) {
            self = .ingredient(id)
        } else if let id = Self.payload(of: identifier, prefix: Self.recipePrefix) {
            self = .recipe(id)
        } else {
            return nil
        }
    }

    private static func payload(of identifier: String, prefix: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let id = String(identifier.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Maintains the app's Core Spotlight index so 库存食材 and 食谱 surface in
/// system search and tap straight back into the app (see `SpotlightRouter`).
///
/// REBUILD STRATEGY: every reindex deletes the whole domain, then re-adds the
/// current rows. Incremental indexing would have to track adds/edits/deletes
/// across every mutating store; at this data size (≤ a few hundred inventory
/// rows, ~1k recipes) the wholesale rebuild is simpler and self-healing — and
/// it naturally drops entries belonging to a previously selected household on
/// a household switch (the rebuild only ever re-adds the CURRENT scope's rows).
///
/// FAILURE POLICY: Spotlight is a re-engagement enhancement, never a data
/// path — index errors are logged (debug) and swallowed so a broken index
/// can't degrade the app, but they are never dropped without a trace.
///
/// CONCURRENCY: a plain final class, not an actor — it holds only immutable
/// state, and Apple documents `CSSearchableIndex` as thread-safe, so the async
/// methods may run on any executor. `@unchecked` only because the system class
/// predates `Sendable` annotations.
final class SpotlightIndexer: @unchecked Sendable {
    /// Domain identifiers — let each corpus be wiped independently in one call.
    static let inventoryDomain = "inventory"
    static let recipesDomain = "recipes"

    /// Spotlight previews show one–two lines; longer text is wasted payload.
    static let descriptionLimit = 80

    private let index: CSSearchableIndex
    private let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "spotlight")

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    /// Whole-domain rebuild of the inventory entries (see REBUILD STRATEGY).
    func reindexInventory(_ items: [Ingredient]) async {
        await rebuild(
            domain: Self.inventoryDomain,
            items: items.compactMap { Self.searchableItem(for: $0) }
        )
    }

    /// Whole-domain rebuild of the recipe entries. The caller pre-merges
    /// shared + custom (`RecipesStore.merge`) so this stays a dumb projection.
    func reindexRecipes(_ recipes: [Recipe]) async {
        await rebuild(
            domain: Self.recipesDomain,
            items: recipes.compactMap { Self.searchableItem(for: $0) }
        )
    }

    private func rebuild(domain: String, items: [CSSearchableItem]) async {
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            if !items.isEmpty {
                try await index.indexSearchableItems(items)
            }
        } catch {
            // Best-effort by design — see FAILURE POLICY above.
            logger.debug(
                "Spotlight \(domain, privacy: .public) rebuild failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: Item construction (pure — unit-tested)

    /// nil for a local-only row (`id == ""`): without a stable id the entry can
    /// neither stay unique in the index nor deep-link back to its detail.
    static func searchableItem(for ingredient: Ingredient) -> CSSearchableItem? {
        guard !ingredient.id.isEmpty else { return nil }
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = ingredient.name
        attributes.contentDescription = ingredientDescription(ingredient)
        attributes.keywords = [ingredient.name, ingredient.category]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
        return CSSearchableItem(
            uniqueIdentifier: SpotlightItemID.ingredient(ingredient.id).identifier,
            domainIdentifier: inventoryDomain,
            attributeSet: attributes
        )
    }

    /// nil for an id-less recipe (defensive — every corpus entry carries one).
    static func searchableItem(for recipe: Recipe) -> CSSearchableItem? {
        guard !recipe.id.isEmpty else { return nil }
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = recipe.name
        attributes.contentDescription = recipeDescription(recipe)
        attributes.keywords = [recipe.name, recipe.category]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        return CSSearchableItem(
            uniqueIdentifier: SpotlightItemID.recipe(recipe.id).identifier,
            domainIdentifier: recipesDomain,
            attributeSet: attributes
        )
    }

    /// "分类 · 数量单位 · 到期日" — every segment optional, joined by " · ".
    static func ingredientDescription(_ ingredient: Ingredient) -> String {
        var segments: [String] = []
        if let category = ingredient.category?.trimmed, !category.isEmpty {
            segments.append(category)
        }
        let amount = "\(ingredient.quantity.trimmed)\(ingredient.unit.trimmed)"
        if !amount.isEmpty {
            segments.append(amount)
        }
        if let expiry = ingredient.expiryDate {
            segments.append(String(localized: "spotlight.ingredient.expiresOn \(expiryFormatter.string(from: expiry))"))
        }
        return segments.joined(separator: " · ")
    }

    /// "分类 · 简介(截断)" — mirrors the ingredient form.
    static func recipeDescription(_ recipe: Recipe) -> String {
        var segments: [String] = []
        let category = recipe.category.trimmed
        if !category.isEmpty {
            segments.append(category)
        }
        let summary = truncated(recipe.description.trimmed, limit: descriptionLimit)
        if !summary.isEmpty {
            segments.append(summary)
        }
        return segments.joined(separator: " · ")
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// "yyyy-MM-dd" matches the in-app detail screen's expiry rendering.
    /// `DateFormatter` is `Sendable` on modern SDKs and this one is immutable
    /// after init, so a plain `static let` is concurrency-safe.
    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
