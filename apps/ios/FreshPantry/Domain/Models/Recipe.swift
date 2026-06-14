import Foundation

/// Sub-value inside `Recipe.ingredients`. A LOSSLESS numeric quantity model:
///
///  * `quantity` is a real JSON `number` (the lower bound for a range), present
///    only when an explicit numeric magnitude exists.
///  * `quantityMax` is the upper bound of a range ("6-15克" → 6…15); absent for
///    a single value.
///  * `unit` carries the measurement unit ("克"/"只"/"ml"/"瓣"); nil when blank.
///  * `note` holds a fuzzy amount ("适量"/"一小把"/"几滴") that has no number.
///
/// Display text is DERIVED via `displayAmount` (there is no stored `amount`
/// field). Decode is backward-compatible: it reads the legacy all-string shape
/// (`quantity`/`unit` strings + `amount`) WITHOUT losing data — string numbers
/// are parsed back to `Double`, "6-15" becomes a range, and a legacy descriptive
/// `amount` (e.g. "一小把") is preserved into `note`.
struct RecipeIngredient: Equatable, Sendable, Codable {
    var name: String
    var quantity: Double?
    var quantityMax: Double?
    var unit: String?
    var note: String?

    init(
        name: String,
        quantity: Double? = nil,
        quantityMax: Double? = nil,
        unit: String? = nil,
        note: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.quantityMax = quantityMax
        self.unit = unit
        self.note = note
    }

    /// Human-readable amount derived from the structured fields (replaces the old
    /// stored `amount`). A numeric quantity renders "<q>[-<max>]<unit>"; a pure
    /// fuzzy amount renders its `note`; nothing → "".
    var displayAmount: String {
        if let quantity {
            var text = QuantityText.formatQuantity(quantity)
            if let quantityMax {
                text += "-" + QuantityText.formatQuantity(quantityMax)
            }
            return text + (unit ?? "")
        }
        if let note { return note }
        if let unit { return unit }  // 仅有单位无数量(用户自建,如"瓣")时仍显示单位,对齐旧 composeAmount
        return ""
    }

    /// Like `displayAmount` but renders the numeric magnitude as a clean cooking
    /// fraction (½ 杯, 1¼ 茶匙) for DISPLAY ONLY (recipe rows, Cook Mode). Storage
    /// and shopping-list details keep using the decimal `displayAmount` so they
    /// stay parseable / mergeable.
    var fractionAmount: String {
        if let quantity {
            var text = QuantityText.formatFraction(quantity)
            if let quantityMax {
                text += "-" + QuantityText.formatFraction(quantityMax)
            }
            return text + (unit ?? "")
        }
        if let note { return note }
        if let unit { return unit }
        return ""
    }

    /// True when there is a numeric magnitude `scaledBy` can scale.
    var isScalable: Bool { quantity != nil }

    /// Multiplies the numeric magnitude (and the range upper bound, if any) by
    /// `factor`. `factor == 1` is a no-op; a non-numeric ingredient (no
    /// `quantity`) is returned unchanged.
    func scaledBy(_ factor: Double) -> RecipeIngredient {
        if factor == 1 { return self }
        guard let quantity else { return self }
        return RecipeIngredient(
            name: name,
            quantity: quantity * factor,
            quantityMax: quantityMax.map { $0 * factor },
            unit: unit,
            note: note
        )
    }

    func copyWith(
        name: String? = nil,
        quantity: Double?? = nil,
        quantityMax: Double?? = nil,
        unit: String?? = nil,
        note: String?? = nil
    ) -> RecipeIngredient {
        RecipeIngredient(
            name: name ?? self.name,
            quantity: quantity ?? self.quantity,
            quantityMax: quantityMax ?? self.quantityMax,
            unit: unit ?? self.unit,
            note: note ?? self.note
        )
    }

    /// `amount` is decode-only (legacy ingestion); it is never encoded.
    private enum CodingKeys: String, CodingKey {
        case name, quantity, quantityMax, unit, note, amount
    }

    /// Lossless encode: only the present keys are written — no empty strings, no
    /// `amount`. `quantity`/`quantityMax` are emitted as JSON numbers.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(quantityMax, forKey: .quantityMax)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(note, forKey: .note)
    }

    /// Backward-compatible decode. Reads BOTH the new numeric shape and the
    /// legacy all-string shape without losing data:
    ///  * `quantity` as a JSON number wins; else a non-empty string `quantity` is
    ///    parsed — "6-15" → quantity 6 + quantityMax 15, otherwise `Double(str)`.
    ///  * `quantityMax` number wins; else the range upper bound parsed above.
    ///  * `unit` trimmed → nil when blank.
    ///  * legacy `amount`: when there is no numeric quantity and no `note`, a
    ///    non-empty descriptive `amount` (e.g. "一小把") is preserved into `note`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = c.decodeLenientIfPresent(String.self, forKey: .name) ?? ""

        var quantity: Double?
        var quantityMax: Double?
        if let n = c.decodeDoubleIfPresent(forKey: .quantity) {
            quantity = n
        } else if let s = c.decodeLenientIfPresent(String.self, forKey: .quantity)?.trimmed,
                  !s.isEmpty {
            if let range = RecipeIngredient.parseRange(s) {
                quantity = range.lower
                quantityMax = range.upper
            } else {
                quantity = Double(s)
            }
        }

        if let n = c.decodeDoubleIfPresent(forKey: .quantityMax) {
            quantityMax = n
        }
        self.quantity = quantity
        self.quantityMax = quantityMax

        let unit = c.decodeLenientIfPresent(String.self, forKey: .unit)?.trimmed
        self.unit = (unit?.isEmpty == false) ? unit : nil

        var note = c.decodeLenientIfPresent(String.self, forKey: .note)?.trimmed
        if note?.isEmpty == true { note = nil }

        // Legacy `amount`: only adopt it as `note` when it carries a fuzzy amount
        // we'd otherwise drop (no numeric quantity, no explicit note). When a
        // numeric quantity exists the legacy amount is just a redundant "200克".
        if quantity == nil, note == nil {
            let legacyAmount = c.decodeLenientIfPresent(String.self, forKey: .amount)?.trimmed
            if let legacyAmount, !legacyAmount.isEmpty {
                note = legacyAmount
            }
        }
        self.note = note
    }

    /// Builds a lossless ingredient from a free-text amount string ("200克",
    /// "6-15克", "一小把", "适量"). A leading number (or hyphen range) becomes
    /// `quantity`/`quantityMax` with the remainder as `unit`; a purely
    /// descriptive amount with no number is preserved as `note`. Used by the
    /// AI/leftover draft path where the amount arrives as a single string.
    static func fromAmountText(name: String, amount: String) -> RecipeIngredient {
        let trimmed = amount.trimmed
        guard !trimmed.isEmpty else { return RecipeIngredient(name: name) }

        // Range form first ("6-15克", "2-3根"): leading "<n>-<n>" then unit text.
        if let range = parseLeadingRange(trimmed) {
            let unit = range.remainder.isEmpty ? nil : range.remainder
            return RecipeIngredient(name: name, quantity: range.lower, quantityMax: range.upper, unit: unit)
        }
        guard let parsed = QuantityText.parseLeadingQuantity(trimmed),
              let value = Double(parsed.magnitude) else {
            // No leading number → fuzzy amount, preserve verbatim in `note`.
            return RecipeIngredient(name: name, note: trimmed)
        }
        let remainder = parsed.remainder.trimmed
        let unit = remainder.isEmpty ? nil : remainder
        return RecipeIngredient(name: name, quantity: value, unit: unit)
    }

    /// Parses a leading numeric range with optional trailing unit text:
    /// "6-15克" → (6, 15, "克"); "2-3" → (2, 3, ""). Returns nil when the head
    /// isn't `<number>-<number>`.
    private static func parseLeadingRange(_ input: String) -> (lower: Double, upper: Double, remainder: String)? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = leadingRangeRe.firstMatch(in: input, options: [], range: range),
              let lowerR = Range(match.range(at: 1), in: input),
              let upperR = Range(match.range(at: 2), in: input),
              let lower = Double(input[lowerR]),
              let upper = Double(input[upperR])
        else { return nil }
        let remainder: String
        if let remR = Range(match.range(at: 3), in: input) {
            remainder = String(input[remR]).trimmed
        } else {
            remainder = ""
        }
        return (lower, upper, remainder)
    }

    private static let leadingRangeRe = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    /// Parses a numeric range like "6-15" / "2-3" / "1.5-2" into its bounds.
    /// Returns nil when the input isn't a two-number hyphen range.
    private static func parseRange(_ input: String) -> (lower: Double, upper: Double)? {
        let parts = input.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let lower = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let upper = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (lower, upper)
    }
}

/// De-duplicates by case-insensitive trimmed name, keeping the FIRST occurrence.
/// Must run at EVERY recipe entry point (matches `shoppingItemNameKey`).
func dedupeRecipeIngredients(_ ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
    var seen = Set<String>()
    var result: [RecipeIngredient] = []
    for ingredient in ingredients {
        if seen.insert(ingredient.name.trimmed.lowercased()).inserted {
            result.append(ingredient)
        }
    }
    return result
}

/// Recipe entity. Identity (Hashable/Equatable) is by `id` ONLY.
struct Recipe: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var category: String
    var difficulty: Int
    var cookingMinutes: Int
    var description: String
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var tags: [String]
    var imageUrl: String?
    var videoUrl: String?
    /// 烹饪贴士/备注:自由文本。自定义菜谱由用户填写;远程菜谱将来可携带。
    var notes: String?
    /// 每份营养(pipeline LLM 估算,展示标注「约」)。复用 OFF 的 `NutritionFacts` 结构,
    /// 但语义是「每份」而非「每 100g」。nil = 该菜未估算营养。
    var nutrition: NutritionFacts?
    /// 每步时长(秒),与 `steps` 索引对齐;某步无明确时长为 nil。整个数组 nil = 未解析。
    /// 由 pipeline 从步骤文本预解析(端上不正则),驱动 Cook Mode 每步倒计时。
    var stepDurations: [Int?]?
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    var syncMetadata: SyncMetadata {
        SyncMetadata(
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            deletedAt: deletedAt
        )
    }

    /// `'难度未设置'` when difficulty <= 0, else `'难度 N/5'` with N clamped 1...5.
    var difficultyLabel: String {
        if difficulty <= 0 { return "难度未设置" }
        let level = min(max(difficulty, 1), 5)
        return "难度 \(level)/5"
    }

    init(
        id: String,
        name: String,
        category: String,
        difficulty: Int,
        cookingMinutes: Int,
        description: String,
        ingredients: [RecipeIngredient],
        steps: [String],
        tags: [String] = [],
        imageUrl: String? = nil,
        videoUrl: String? = nil,
        notes: String? = nil,
        nutrition: NutritionFacts? = nil,
        stepDurations: [Int?]? = nil,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.difficulty = difficulty
        self.cookingMinutes = cookingMinutes
        self.description = description
        // Dedupe at the value-type entry point too (every entry point routes here).
        self.ingredients = dedupeRecipeIngredients(ingredients)
        self.steps = steps
        self.tags = tags
        self.imageUrl = imageUrl
        self.videoUrl = videoUrl
        self.notes = notes
        self.nutrition = nutrition
        self.stepDurations = stepDurations
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, difficulty, cookingMinutes, description
        case ingredients, steps, tags, imageUrl, videoUrl, notes, nutrition, stepDurations
        case remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(cookingMinutes, forKey: .cookingMinutes)
        try c.encode(description, forKey: .description)
        try c.encode(ingredients, forKey: .ingredients)
        try c.encode(steps, forKey: .steps)
        try c.encode(tags, forKey: .tags)
        try c.encodeAlways(imageUrl, forKey: .imageUrl)
        try c.encodeAlways(videoUrl, forKey: .videoUrl)
        try c.encodeAlways(notes, forKey: .notes)
        try c.encodeIfPresent(nutrition, forKey: .nutrition)
        try c.encodeIfPresent(stepDurations, forKey: .stepDurations)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawIngredients = c.decodeLenientIfPresent([RecipeIngredient].self, forKey: .ingredients) ?? []
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            name: c.decodeLenientIfPresent(String.self, forKey: .name) ?? "",
            category: c.decodeLenientIfPresent(String.self, forKey: .category) ?? "",
            difficulty: c.decodeIntIfPresent(forKey: .difficulty) ?? 0,
            cookingMinutes: c.decodeIntIfPresent(forKey: .cookingMinutes) ?? 30,
            description: c.decodeLenientIfPresent(String.self, forKey: .description) ?? "",
            ingredients: rawIngredients,
            steps: c.decodeLenientIfPresent([String].self, forKey: .steps) ?? [],
            tags: c.decodeLenientIfPresent([String].self, forKey: .tags) ?? [],
            imageUrl: c.decodeLenientIfPresent(String.self, forKey: .imageUrl),
            videoUrl: c.decodeLenientIfPresent(String.self, forKey: .videoUrl),
            notes: c.decodeLenientIfPresent(String.self, forKey: .notes),
            nutrition: c.decodeLenientIfPresent(NutritionFacts.self, forKey: .nutrition),
            stepDurations: c.decodeLenientIfPresent([Int?].self, forKey: .stepDurations),
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        category: String? = nil,
        difficulty: Int? = nil,
        cookingMinutes: Int? = nil,
        description: String? = nil,
        ingredients: [RecipeIngredient]? = nil,
        steps: [String]? = nil,
        tags: [String]? = nil,
        imageUrl: String? = nil,
        videoUrl: String? = nil,
        notes: String? = nil,
        nutrition: NutritionFacts? = nil,
        stepDurations: [Int?]? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> Recipe {
        Recipe(
            id: id ?? self.id,
            name: name ?? self.name,
            category: category ?? self.category,
            difficulty: difficulty ?? self.difficulty,
            cookingMinutes: cookingMinutes ?? self.cookingMinutes,
            description: description ?? self.description,
            ingredients: ingredients ?? self.ingredients,
            steps: steps ?? self.steps,
            tags: tags ?? self.tags,
            imageUrl: imageUrl ?? self.imageUrl,
            videoUrl: videoUrl ?? self.videoUrl,
            notes: notes ?? self.notes,
            nutrition: nutrition ?? self.nutrition,
            stepDurations: stepDurations ?? self.stepDurations,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}

extension String {
    /// Dart `.trim()` parity — strips leading/trailing whitespace & newlines.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
