import Foundation
import os

/// Result returned from an Open Food Facts name search (product name + image).
/// Mirrors the Dart `FoodSearchResult`.
struct FoodSearchResult: Equatable, Sendable {
    let productName: String
    let imageUrl: String?
}

/// Queries Open Food Facts for product name-search and full food details (incl.
/// per-100g nutrition); maps OFF `categories_tags` to app categories.
///
/// Stateless `enum` namespace (the Dart `OpenFoodFactsService` is all-static).
/// Ported VERBATIM from `lib/services/open_food_facts_service.dart` — the
/// category-keyword map (FIRST-match wins), the product quality score, and the
/// exact nutriment keys are user-visible (services INVARIANTS #9/#10).
///
/// Every lookup is BEST-EFFORT: transport / parse failures are caught, logged,
/// and turned into `nil` so the detail screen never crashes on a flaky network.
enum OpenFoodFactsService {
    // MARK: Constants

    private static let searchUrl = "https://world.openfoodfacts.org/cgi/search.pl"
    private static let searchALiciousUrl = "https://search.openfoodfacts.org/search"
    private static let productUrl = "https://world.openfoodfacts.org/api/v2/product"
    private static let detailsFields =
        "product_name,generic_name,categories_tags,categories,"
        + "image_front_small_url,image_front_url,image_small_url,image_url,"
        + "image_thumb_url,completeness,nutriments,"
        + "nutriscore_grade,nova_group,ecoscore_grade,additives_tags"
    private static let timeout: TimeInterval = 8
    private static let retryCount = 1
    private static let retryDelay: TimeInterval = 0.5
    private static let maxSearchResults = 1
    private static let maxDetailSearchResults = 8
    private static let headers = ["User-Agent": "FreshPantry/1.0 (SwiftUI)"]

    /// Category keyword mapping: OFF `categories_tags` substring → app category.
    /// Ported VERBATIM from the Dart `_categoryMapping` (FIRST-match wins,
    /// INVARIANT #10). Stored as an ORDERED array (not a dictionary) so the
    /// FIRST-declared key wins on a tie — a Swift dictionary's unordered
    /// iteration would break that determinism.
    // The Chinese literals below are `FoodCategories.*` domain-identity values
    // (e.g. `dairyAndEggs = "乳品蛋类"`) — the same category strings persisted on
    // `Ingredient.category` and rendered app-wide (Inventory/Recipes/etc, all
    // outside Settings/Services). Localizing category display is a cross-cutting
    // change beyond this file's scope; these are data-matching literals, not new
    // UI text authored here. // i18n:ignore domain category identity, not new UI text
    static let categoryMapping: [(key: String, value: String)] = [
        // 乳品蛋类
        ("dairy", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("milk", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("cheese", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("yogurt", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("butter", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("cream", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("egg", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("lait", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        ("fromage", "乳品蛋类"), // i18n:ignore domain category identity, not new UI text
        // 果蔬生鲜
        ("fruit", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        ("vegetable", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        ("legume", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        ("salad", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        ("produce", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        ("fresh", "果蔬生鲜"), // i18n:ignore domain category identity, not new UI text
        // 肉类海鲜
        ("meat", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("beef", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("pork", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("chicken", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("poultry", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("fish", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("seafood", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("shrimp", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("viande", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        ("poisson", "肉类海鲜"), // i18n:ignore domain category identity, not new UI text
        // 香料草本
        ("spice", "香料草本"), // i18n:ignore domain category identity, not new UI text
        ("herb", "香料草本"), // i18n:ignore domain category identity, not new UI text
        ("seasoning", "香料草本"), // i18n:ignore domain category identity, not new UI text
        ("pepper", "香料草本"), // i18n:ignore domain category identity, not new UI text
        ("salt", "香料草本"), // i18n:ignore domain category identity, not new UI text
        ("condiment", FoodCategories.herbsAndSpices),
        ("sauce", FoodCategories.herbsAndSpices),
        ("épice", "香料草本"), // i18n:ignore domain category identity, not new UI text
        // Broad shelf-stable catchall.
        ("cereal", FoodCategories.other),
        ("pasta", FoodCategories.other),
        ("rice", FoodCategories.other),
        ("bread", FoodCategories.other),
        ("flour", FoodCategories.other),
        ("oil", FoodCategories.other),
        ("sugar", FoodCategories.other),
        ("snack", FoodCategories.other),
        ("beverage", FoodCategories.other),
        ("drink", FoodCategories.other),
        ("canned", FoodCategories.other),
        ("conserve", FoodCategories.other),
        ("biscuit", FoodCategories.other),
        ("chocolate", FoodCategories.other),
        ("coffee", FoodCategories.other),
        ("tea", FoodCategories.other),
        ("juice", FoodCategories.other),
        ("water", FoodCategories.other),
        ("noodle", FoodCategories.other),
        ("grain", FoodCategories.other),
    ]

    // MARK: Name search

    /// Search for a product by name. Returns the best match as a
    /// `FoodSearchResult`, or `nil` if nothing relevant is found / on any error.
    static func searchByName(
        _ name: String,
        session: URLSession = .shared
    ) async -> FoodSearchResult? {
        guard let uri = makeURL(
            searchUrl,
            query: [
                "search_terms": name,
                "search_simple": "1",
                "action": "process",
                "json": "1",
                "page_size": "\(maxSearchResults)",
                "fields": "product_name,image_front_small_url",
            ]
        ) else { return nil }

        do {
            let (data, response) = try await fetch(uri, session: session)
            guard response.statusCode == 200 else { return nil }
            guard let json = jsonObject(data),
                  let products = json["products"] as? [Any],
                  let first = products.first as? [String: Any],
                  let productName = jsonString(first["product_name"]), !productName.trimmed.isEmpty
            else { return nil }
            return FoodSearchResult(
                productName: productName.trimmed,
                imageUrl: jsonString(first["image_front_small_url"])
            )
        } catch {
            log("searchByName", error)
            return nil
        }
    }

    // MARK: Details lookup

    /// Lookup basic food details by barcode first, then by name. Best-effort —
    /// any transport / parse error is caught, logged, and returns `nil`.
    static func lookupDetails(
        name: String,
        barcode: String? = nil,
        fetchedAt: Date = Date(),
        session: URLSession = .shared
    ) async -> FoodDetails? {
        do {
            let trimmedBarcode = barcode?.trimmed
            if let trimmedBarcode, !trimmedBarcode.isEmpty {
                return try await lookupByBarcode(
                    barcode: trimmedBarcode,
                    fallbackName: name,
                    fetchedAt: fetchedAt,
                    session: session
                )
            }

            for searchTerm in searchTermsFor(name) {
                if let details = try await lookupByName(
                    searchTerm: searchTerm,
                    fallbackName: name,
                    fetchedAt: fetchedAt,
                    session: session
                ) {
                    return details
                }
            }
            return nil
        } catch {
            log("lookupDetails", error)
            return nil
        }
    }

    private static func lookupByBarcode(
        barcode: String,
        fallbackName: String,
        fetchedAt: Date,
        session: URLSession
    ) async throws -> FoodDetails? {
        guard let encoded = barcode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let uri = URL(string: "\(productUrl)/\(encoded)?fields=\(detailsFields.urlQueryEncoded)")
        else { return nil }

        let (data, response) = try await fetch(uri, session: session)
        guard response.statusCode == 200 else { return nil }
        guard let json = jsonObject(data),
              let product = json["product"] as? [String: Any]
        else { return nil }

        return productToFoodDetails(
            product,
            fallbackName: fallbackName,
            fetchedAt: fetchedAt,
            preferFallbackDisplayName: false
        )
    }

    private static func lookupByName(
        searchTerm: String,
        fallbackName: String,
        fetchedAt: Date,
        session: URLSession
    ) async throws -> FoodDetails? {
        // 1) Legacy search.pl
        if let legacyUri = makeURL(
            searchUrl,
            query: [
                "search_terms": searchTerm,
                "search_simple": "1",
                "action": "process",
                "json": "1",
                "page_size": "\(maxDetailSearchResults)",
                "fields": detailsFields,
            ]
        ) {
            let (data, response) = try await fetch(legacyUri, session: session)
            if response.statusCode == 200,
               let json = jsonObject(data),
               let product = bestProduct(json["products"], fallbackName: fallbackName) {
                return productToFoodDetails(
                    product,
                    fallbackName: fallbackName,
                    fetchedAt: fetchedAt,
                    preferFallbackDisplayName: true
                )
            }
        }

        // 2) SearchALicious fallback
        guard let searchALiciousUri = makeURL(
            searchALiciousUrl,
            query: [
                "q": searchTerm,
                "page_size": "\(maxDetailSearchResults)",
                "fields": detailsFields,
            ]
        ) else { return nil }

        let (data, response) = try await fetch(searchALiciousUri, session: session)
        guard response.statusCode == 200,
              let json = jsonObject(data),
              let product = bestProduct(json["hits"], fallbackName: fallbackName)
        else { return nil }

        return productToFoodDetails(
            product,
            fallbackName: fallbackName,
            fetchedAt: fetchedAt,
            preferFallbackDisplayName: true
        )
    }

    // MARK: Category resolution

    /// Match OFF `categories_tags` against the keyword map. Returns the first
    /// matched app category or `nil`. FIRST-match wins (INVARIANT #10).
    static func resolveCategory(_ tags: [Any]?) -> String? {
        guard let tags, !tags.isEmpty else { return nil }
        for tag in tags {
            let lower = "\(tag)".lowercased()
            for entry in categoryMapping where lower.contains(entry.key) {
                return entry.value
            }
        }
        return nil
    }

    // MARK: Best-product selection

    /// argmax of `productQualityScore` over a products/hits array. Mirrors the
    /// Dart `_bestProduct`.
    static func bestProduct(_ productsValue: Any?, fallbackName: String) -> [String: Any]? {
        guard let products = productsValue as? [Any], !products.isEmpty else { return nil }

        var best: [String: Any]?
        var bestScore = -Double.infinity
        for value in products {
            guard let product = value as? [String: Any] else { continue }
            let score = productQualityScore(product, fallbackName: fallbackName)
            if score > bestScore {
                best = product
                bestScore = score
            }
        }
        return best
    }

    /// Product quality score. Ported VERBATIM (user-visible best-match selection,
    /// INVARIANT #10): image +80; completeness*30 (−100 if <0.25); name present
    /// +10, exact +70 / contains +50, extra-length penalty −5/char; generic +3.
    static func productQualityScore(_ product: [String: Any], fallbackName: String) -> Double {
        var score = 0.0
        let query = fallbackName.trimmed.lowercased()

        if imageUrlForProduct(product) != nil {
            score += 80
        }

        if let completeness = jsonDouble(product["completeness"]) {
            let normalizedCompleteness = min(max(completeness, 0), 1)
            score += normalizedCompleteness * 30
            if normalizedCompleteness < 0.25 {
                score -= 100
            }
        }

        if let productName = jsonString(product["product_name"]), !productName.trimmed.isEmpty {
            let normalizedName = productName.trimmed.lowercased()
            score += 10
            if !query.isEmpty {
                if normalizedName == query {
                    score += 70
                } else if normalizedName.contains(query) {
                    score += 50
                }

                let extraLength = normalizedName.count - query.count
                if extraLength > 0 {
                    score -= Double(extraLength) * 5
                }
            }
        }

        if let genericName = jsonString(product["generic_name"]), !genericName.trimmed.isEmpty {
            score += 3
        }

        return score
    }

    // MARK: Product → FoodDetails

    /// Map an OFF product object to a `FoodDetails`. Mirrors the Dart
    /// `_productToFoodDetails` (displayName precedence flips on
    /// `preferFallbackDisplayName`).
    static func productToFoodDetails(
        _ product: [String: Any],
        fallbackName: String,
        fetchedAt: Date,
        preferFallbackDisplayName: Bool
    ) -> FoodDetails? {
        let displayName = firstNonEmpty(
            preferFallbackDisplayName
                ? [fallbackName, product["product_name"], product["generic_name"]]
                : [product["product_name"], product["generic_name"], fallbackName]
        )
        guard let displayName, !displayName.trimmed.isEmpty else { return nil }
        let trimmedDisplayName = displayName.trimmed

        let categoriesTags = product["categories_tags"] as? [Any]
        let category = resolveCategory(categoriesTags) ?? FoodKnowledge.categoryFor(fallbackName)
        let defaults = FoodKnowledge.lookup(fallbackName) ?? FoodKnowledge.lookup(trimmedDisplayName)

        return FoodDetails(
            displayName: trimmedDisplayName,
            description: descriptionForProduct(product, category: category),
            imageUrl: imageUrlForProduct(product),
            category: FoodCategories.dropdownValue(category),
            storage: defaults?.storage ?? storageForCategory(category),
            shelfLifeDays: defaults?.shelfLifeDays,
            source: "Open Food Facts",
            fetchedAt: fetchedAt,
            nutrition: nutritionForProduct(product)
        )
    }

    static func nutritionForProduct(_ product: [String: Any]) -> NutritionFacts? {
        // Macros (from `nutriments`) PLUS product-level grades (Nutri-Score / NOVA
        // / Eco-Score / additives), so a product with only a grade still surfaces.
        NutritionFacts.fromOffProduct(product)
    }

    static func descriptionForProduct(_ product: [String: Any], category: String) -> String {
        if let genericName = firstNonEmpty([product["generic_name"]]), !genericName.trimmed.isEmpty {
            return genericName.trimmed
        }
        // Kept Chinese (not `String(localized:)`) on purpose: `isPlaceholderFoodDescription`
        // below detects this exact template via literal Chinese prefix/suffix
        // matching. Localizing the generated text would silently break that
        // detection for non-zh-Hans locales (a real placeholder would then read as
        // "real" content). Needs a non-string-sniffing redesign (e.g. a sentinel
        // enum) before this can be localized — flagged as a follow-up, not done here.
        return "Open Food Facts 记录的\(category)食品。" // i18n:ignore placeholder-detection template, see note above // i18n:ignore ——技术债:该兜底描述实际会渲染给用户,但与 isPlaceholderFoodDescription 字符串嗅探耦合,需先重构检测机制;见 task-6-report 遗留事项
    }

    static func storageForCategory(_ category: String) -> IconType {
        switch FoodCategories.dropdownValue(category) {
        case FoodCategories.dairyAndEggs, FoodCategories.freshProduce, FoodCategories.meatAndSeafood:
            return .fridge
        default:
            return .pantry
        }
    }

    static func imageUrlForProduct(_ product: [String: Any]) -> String? {
        firstNonEmpty([
            product["image_front_small_url"],
            product["image_small_url"],
            product["image_front_url"],
            product["image_url"],
            product["image_thumb_url"],
        ])
    }

    /// Search terms for a name: the Chinese name first, then the FoodKnowledge
    /// English name when distinct (case-insensitive). Mirrors `_searchTermsFor`.
    static func searchTermsFor(_ name: String) -> [String] {
        var terms: [String] = []
        let trimmedName = name.trimmed
        if !trimmedName.isEmpty {
            terms.append(trimmedName)
        }

        if let englishName = FoodKnowledge.englishName(name) {
            let trimmedEnglishName = englishName.trimmed
            if !trimmedEnglishName.isEmpty,
               trimmedEnglishName.lowercased() != trimmedName.lowercased() {
                terms.append(trimmedEnglishName)
            }
        }

        return terms
    }

    // MARK: HTTP

    private static func fetch(_ url: URL, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        try await fetchWithRetry(
            url,
            session: session,
            timeout: timeout,
            retryDelay: retryDelay,
            retryCount: retryCount,
            headers: headers
        )
    }

    // MARK: JSON cast helpers (parity with the Dart `asJson*` casts)

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// First non-empty trimmed string from a list of OFF JSON values. Mirrors
    /// the Dart `_firstNonEmpty`.
    private static func firstNonEmpty(_ values: [Any?]) -> String? {
        for value in values {
            if let text = jsonString(value)?.trimmed, !text.isEmpty { return text }
        }
        return nil
    }

    private static func jsonString(_ value: Any?) -> String? {
        value as? String
    }

    private static func jsonDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmed) }
        return nil
    }

    private static func makeURL(_ base: String, query: [String: String]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        // Preserve insertion-independent ordering not required by OFF; build the
        // items directly so `URLComponents` handles percent-encoding.
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }

    private static let logger = Logger(subsystem: "com.sunpebble.freshpantry", category: "openFoodFacts")

    private static func log(_ context: String, _ error: Error) {
        // Best-effort lookup: surface the failure (not silently hidden) but never
        // propagate it to the detail screen. Use os.Logger (subsystem-scoped,
        // filterable in Console) instead of a bare print to stdout.
        logger.error("\(context, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
    }
}

private extension String {
    /// Percent-encode for use inside a raw URL query string (the `fields=` value
    /// has commas that must survive).
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

/// Whether a description is a system-generated placeholder rather than a real
/// food description (so presentation can hide it). Ported from
/// `lib/storage/food_details_repo.dart` `isPlaceholderFoodDescription` — the
/// single authority mirroring the three placeholder templates: the OFF generic
/// line (`Open Food Facts 记录的<category>食品。`) and the two local-fallback
/// lines. Keep in sync if any template changes.
func isPlaceholderFoodDescription(_ description: String) -> Bool {
    let trimmed = description.trimmed
    if trimmed.isEmpty { return true }
    // Literal-text sniffing against the (deliberately unlocalized, see
    // `descriptionForProduct`) generated placeholder templates.
    if trimmed.hasPrefix("Open Food Facts 记录的") && trimmed.hasSuffix("食品。") { // i18n:ignore placeholder-detection template match, see descriptionForProduct
        return true
    }
    if trimmed.hasPrefix("建议存放在") { return true } // i18n:ignore placeholder-detection template match, see descriptionForProduct
    if trimmed.hasPrefix("暂无联网详情") { return true } // i18n:ignore placeholder-detection template match, see descriptionForProduct
    return false
}
