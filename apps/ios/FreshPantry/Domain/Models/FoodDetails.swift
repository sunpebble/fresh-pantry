import Foundation

/// Per-100g macro nutrition facts + at-a-glance OFF grades (Open Food Facts).
/// Every field is nullable. The grades turn "记录" into a buy-decision aid:
///  * `nutriScore` a–e (overall nutritional quality, Yuka-style)
///  * `novaGroup` 1–4 (processing degree; 4 = ultra-processed)
///  * `ecoScore` a–e (environmental impact — ties减废=减碳 to the app theme)
struct NutritionFacts: Equatable, Sendable, Codable {
    var energyKcal: Double?  // kcal / 100g
    var protein: Double?     // g / 100g
    var carbs: Double?       // g / 100g
    var fat: Double?         // g / 100g
    var nutriScore: String?  // "a"…"e" (lowercased)
    var novaGroup: Int?      // 1…4
    var ecoScore: String?    // "a"…"e" (lowercased)
    var additivesCount: Int? // count of additives_tags

    init(
        energyKcal: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        nutriScore: String? = nil,
        novaGroup: Int? = nil,
        ecoScore: String? = nil,
        additivesCount: Int? = nil
    ) {
        self.energyKcal = energyKcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.nutriScore = nutriScore
        self.novaGroup = novaGroup
        self.ecoScore = ecoScore
        self.additivesCount = additivesCount
    }

    var hasAny: Bool {
        energyKcal != nil || protein != nil || carbs != nil || fat != nil
            || nutriScore != nil || novaGroup != nil || ecoScore != nil || additivesCount != nil
    }

    /// True when any at-a-glance grade is present (drives the badge row).
    var hasGrades: Bool {
        nutriScore != nil || novaGroup != nil || ecoScore != nil || additivesCount != nil
    }

    /// Build from an OFF `nutriments` map (per-100g keys) ONLY. Returns nil when
    /// no usable macro is present. Grades live at the product level — see
    /// `fromOffProduct`.
    static func fromOffNutriments(_ n: [String: Any]) -> NutritionFacts? {
        let facts = NutritionFacts(
            energyKcal: toDouble(n["energy-kcal_100g"]),
            protein: toDouble(n["proteins_100g"]),
            carbs: toDouble(n["carbohydrates_100g"]),
            fat: toDouble(n["fat_100g"])
        )
        return facts.hasAny ? facts : nil
    }

    /// Build from a full OFF product object: macros from `nutriments` PLUS the
    /// product-level grades (`nutriscore_grade`/`nova_group`/`ecoscore_grade`/
    /// `additives_tags`). Returns nil only when nothing usable is present.
    static func fromOffProduct(_ product: [String: Any]) -> NutritionFacts? {
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let facts = NutritionFacts(
            energyKcal: toDouble(nutriments["energy-kcal_100g"]),
            protein: toDouble(nutriments["proteins_100g"]),
            carbs: toDouble(nutriments["carbohydrates_100g"]),
            fat: toDouble(nutriments["fat_100g"]),
            nutriScore: grade(product["nutriscore_grade"]),
            novaGroup: novaValue(product["nova_group"]),
            ecoScore: grade(product["ecoscore_grade"]),
            additivesCount: additivesCount(product["additives_tags"])
        )
        return facts.hasAny ? facts : nil
    }

    /// Normalizes an OFF grade ("A"/"a"/"unknown"/"not-applicable") to a clean
    /// lowercase a–e, else nil.
    private static func grade(_ value: Any?) -> String? {
        guard let raw = (value as? String)?.trimmed.lowercased(), raw.count == 1,
              "abcde".contains(raw) else { return nil }
        return raw
    }

    private static func novaValue(_ value: Any?) -> Int? {
        let n: Int?
        if let v = value as? Int { n = v }
        else if let v = value as? NSNumber { n = v.intValue }
        else if let v = value as? Double { n = Int(v) }
        else if let v = (value as? String)?.trimmed { n = Int(v) }
        else { n = nil }
        guard let n, (1...4).contains(n) else { return nil }
        return n
    }

    private static func additivesCount(_ value: Any?) -> Int? {
        guard let tags = value as? [Any] else { return nil }
        return tags.isEmpty ? nil : tags.count
    }

    static func toDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmed) }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case energyKcal, protein, carbs, fat, nutriScore, novaGroup, ecoScore, additivesCount
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeAlways(energyKcal, forKey: .energyKcal)
        try c.encodeAlways(protein, forKey: .protein)
        try c.encodeAlways(carbs, forKey: .carbs)
        try c.encodeAlways(fat, forKey: .fat)
        try c.encodeAlways(nutriScore, forKey: .nutriScore)
        try c.encodeAlways(novaGroup, forKey: .novaGroup)
        try c.encodeAlways(ecoScore, forKey: .ecoScore)
        try c.encodeAlways(additivesCount, forKey: .additivesCount)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal = c.decodeDoubleIfPresent(forKey: .energyKcal)
        protein = c.decodeDoubleIfPresent(forKey: .protein)
        carbs = c.decodeDoubleIfPresent(forKey: .carbs)
        fat = c.decodeDoubleIfPresent(forKey: .fat)
        nutriScore = c.decodeLenientIfPresent(String.self, forKey: .nutriScore)
        novaGroup = c.decodeIntIfPresent(forKey: .novaGroup)
        ecoScore = c.decodeLenientIfPresent(String.self, forKey: .ecoScore)
        additivesCount = c.decodeIntIfPresent(forKey: .additivesCount)
    }
}

/// Cached enriched food metadata (OFF/AI) + per-100g nutrition. Cache value
/// object — `toJson` writes a literal `cacheVersion` that must move in
/// lockstep with the cache constant or stale caches won't invalidate.
struct FoodDetails: Equatable, Sendable, Codable {
    /// Cache schema version literal — 5 added nutrition; 6 added the OFF grades
    /// (Nutri-Score/NOVA/Eco-Score/additives) so stale caches refresh to fill them.
    static let cacheVersion = 6

    var displayName: String
    var description: String
    var imageUrl: String?
    var category: String
    var storage: IconType
    var shelfLifeDays: Int?
    var source: String
    var fetchedAt: Date
    var nutrition: NutritionFacts?

    init(
        displayName: String,
        description: String,
        imageUrl: String?,
        category: String,
        storage: IconType,
        shelfLifeDays: Int?,
        source: String,
        fetchedAt: Date,
        nutrition: NutritionFacts? = nil
    ) {
        self.displayName = displayName
        self.description = description
        self.imageUrl = imageUrl
        self.category = category
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
        self.source = source
        self.fetchedAt = fetchedAt
        self.nutrition = nutrition
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, description, imageUrl, category, storage
        case shelfLifeDays, source, fetchedAt, nutrition, cacheVersion
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(description, forKey: .description)
        try c.encodeAlways(imageUrl, forKey: .imageUrl)
        try c.encode(category, forKey: .category)
        try c.encode(storage.rawValue, forKey: .storage)
        try c.encodeAlways(shelfLifeDays, forKey: .shelfLifeDays)
        try c.encode(source, forKey: .source)
        try c.encode(JSONDate.iso8601(fetchedAt), forKey: .fetchedAt)
        try c.encodeAlways(nutrition, forKey: .nutrition)
        try c.encode(FoodDetails.cacheVersion, forKey: .cacheVersion)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? ""
        description = c.decodeLenientIfPresent(String.self, forKey: .description) ?? ""
        imageUrl = c.decodeLenientIfPresent(String.self, forKey: .imageUrl)
        category = c.decodeLenientIfPresent(String.self, forKey: .category) ?? ""
        storage = IconType.fromName(c.decodeLenientIfPresent(String.self, forKey: .storage))
        shelfLifeDays = c.decodeIntIfPresent(forKey: .shelfLifeDays)
        source = c.decodeLenientIfPresent(String.self, forKey: .source) ?? ""
        // tryParse OR epoch-0-UTC fallback when missing/unparseable.
        let rawFetchedAt = c.decodeLenientIfPresent(String.self, forKey: .fetchedAt)
        fetchedAt = JSONDate.fromJSONValue(rawFetchedAt) ?? Date(timeIntervalSince1970: 0)
        nutrition = c.decodeLenientIfPresent(NutritionFacts.self, forKey: .nutrition)
    }
}
