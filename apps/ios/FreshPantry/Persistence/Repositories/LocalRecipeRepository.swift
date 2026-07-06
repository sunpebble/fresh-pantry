import Foundation

/// Test/local payload loader for a HowToCook JSON array. Production no longer
/// ships `howtocook.json`; the shared catalog comes from DB/cache.
///
/// An `actor` so the decode-and-cache happens off the main actor and is safe
/// under Swift 6 strict concurrency.
actor LocalRecipeRepository {
    /// Explicit JSON payload override (tests inject a fixed corpus; production nil).
    private let payloadOverride: Data?
    private var cache: [Recipe]?

    init() {
        self.payloadOverride = nil
    }

    /// Test seam: decode this exact JSON array.
    init(payload: Data) {
        self.payloadOverride = payload
    }

    /// Decodes the payload once and caches it. Production defaults to `[]`;
    /// DB/cache are handled by `RecipeCatalogLoader`.
    func loadAll() -> [Recipe] {
        if let cache { return cache }
        let recipes = payloadOverride.map(Self.decode(data:)) ?? []
        cache = recipes
        return recipes
    }

    /// Per-entry resilient decode (exposed for tests against an injected payload).
    /// The top level must be a JSON array; each element decodes through `Recipe`'s
    /// lenient `Codable`, and any element that fails (wrong type, missing keys) is
    /// skipped — the rest are preserved. Returns `[]` if the top level isn't an
    /// array. Never throws.
    static func decode(data: Data) -> [Recipe] {
        guard let lossy = try? JSONDecoder().decode(LossyRecipeArray.self, from: data) else {
            return []
        }
        return lossy.recipes
    }
}

/// Resilient array container: decodes a JSON array of recipes, skipping any
/// element that fails to decode rather than failing the whole array. Each
/// element is advanced past on failure by decoding a throwaway value, so one bad
/// entry can't desync the unkeyed container.
private struct LossyRecipeArray: Decodable {
    let recipes: [Recipe]

    /// Skip token: decodes ANY single JSON value (scalar, array, or object) via a
    /// single-value container, consuming exactly one element of the unkeyed
    /// container so iteration stays aligned after a malformed recipe. Never throws
    /// for a well-formed JSON value.
    private struct AnyJSON: Decodable {
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode(String.self)) != nil { return }
            if (try? container.decode([AnyJSON].self)) != nil { return }
            _ = try? container.decode([String: AnyJSON].self)
        }
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Recipe] = []
        while !container.isAtEnd {
            if let recipe = try? container.decode(Recipe.self) {
                decoded.append(recipe)
            } else {
                // Advance past the unparseable element to keep the cursor aligned.
                _ = try? container.decode(AnyJSON.self)
            }
        }
        recipes = decoded
    }
}
