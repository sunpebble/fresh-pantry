import Foundation

/// Weekly meal-plan record: one planned dish on one LOCAL calendar day.
/// One record == one dish. Identity (Hashable/Equatable) is by `id` ONLY.
///
/// `date` is normalized to local midnight (year/month/day) and serialized as
/// `"yyyy-MM-dd"` (NOT ISO). `fromJson` THROWS on missing/unparseable date so
/// the repo layer can catch+skip a dirty row (no silent fallback).
struct MealPlanEntry: Hashable, Sendable, Codable {
    var id: String
    var date: Date
    var recipeId: String
    var recipeName: String
    var recipeImageUrl: String?
    var servings: Int
    var done: Bool
    /// Free-text title for a NON-recipe entry (e.g. "外卖"/"泡面") — `recipeId` is
    /// empty for these. nil for a normal recipe dish.
    var title: String?
    /// Optional meal slot: 早餐/午餐/晚餐/点心. nil = unslotted.
    var mealType: String?
    /// Marks this as a leftover serving — excluded from 缺料 shopping and from
    /// cook-time deduction (it was already cooked).
    var isLeftover: Bool
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    /// A free-text note (no recipe attached).
    var isNote: Bool { recipeId.isEmpty }
    /// What the row shows: the recipe name, or the note title for a note.
    var displayTitle: String {
        recipeName.isEmpty ? (title ?? "") : recipeName
    }

    var syncMetadata: SyncMetadata {
        SyncMetadata(
            remoteVersion: remoteVersion,
            clientUpdatedAt: clientUpdatedAt,
            deletedAt: deletedAt
        )
    }

    init(
        id: String,
        date: Date,
        recipeId: String,
        recipeName: String,
        recipeImageUrl: String? = nil,
        servings: Int = 1,
        done: Bool = false,
        title: String? = nil,
        mealType: String? = nil,
        isLeftover: Bool = false,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.date = MealPlanEntry.dateOnly(date)
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.recipeImageUrl = recipeImageUrl
        self.servings = servings
        self.done = done
        self.title = title
        self.mealType = mealType
        self.isLeftover = isLeftover
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    /// Truncates a date to LOCAL midnight (year/month/day only), mirroring Dart
    /// `DateTime(value.year, value.month, value.day)`.
    static func dateOnly(_ value: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        return calendar.date(from: components) ?? value
    }

    /// Stable `yyyy-MM-dd` key (local, zero-padded) for grouping + serialization.
    static func dateKey(_ value: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: dateOnly(value))
        let year = String(format: "%04d", c.year ?? 0)
        let month = String(format: "%02d", c.month ?? 0)
        let day = String(format: "%02d", c.day ?? 0)
        return "\(year)-\(month)-\(day)"
    }

    /// Parses a `yyyy-MM-dd` (or full-ISO legacy) string into a LOCAL-midnight
    /// date, mirroring Dart `_parseDate` -> `DateTime.tryParse` + `dateOnly`.
    static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String, !string.trimmed.isEmpty else { return nil }
        let trimmed = string.trimmed
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: trimmed) { return dateOnly(date) }
        // Legacy full-ISO timestamp fallback (parsed then truncated to local day).
        if let date = JSONDate.parse(trimmed) { return dateOnly(date) }
        return nil
    }

    static func == (lhs: MealPlanEntry, rhs: MealPlanEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, date, recipeId, recipeName, recipeImageUrl, servings, done
        case title, mealType, isLeftover
        case remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(MealPlanEntry.dateKey(date), forKey: .date)
        try c.encode(recipeId, forKey: .recipeId)
        try c.encode(recipeName, forKey: .recipeName)
        try c.encodeAlways(recipeImageUrl, forKey: .recipeImageUrl)
        try c.encode(servings, forKey: .servings)
        try c.encode(done, forKey: .done)
        try c.encodeAlways(title, forKey: .title)
        try c.encodeAlways(mealType, forKey: .mealType)
        try c.encode(isLeftover, forKey: .isLeftover)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = c.decodeLenientIfPresent(String.self, forKey: .date)
        guard let date = MealPlanEntry.parseDate(rawDate) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: c.codingPath,
                    debugDescription: "MealPlanEntry.date missing or unparseable"
                )
            )
        }
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            date: date,
            recipeId: c.decodeLenientIfPresent(String.self, forKey: .recipeId) ?? "",
            recipeName: c.decodeLenientIfPresent(String.self, forKey: .recipeName) ?? "",
            recipeImageUrl: c.decodeLenientIfPresent(String.self, forKey: .recipeImageUrl),
            servings: c.decodeIntIfPresent(forKey: .servings) ?? 1,
            done: c.decodeLenientIfPresent(Bool.self, forKey: .done) ?? false,
            title: c.decodeLenientIfPresent(String.self, forKey: .title),
            mealType: c.decodeLenientIfPresent(String.self, forKey: .mealType),
            isLeftover: c.decodeLenientIfPresent(Bool.self, forKey: .isLeftover) ?? false,
            remoteVersion: c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0,
            clientUpdatedAt: c.decodeISODateIfPresent(forKey: .clientUpdatedAt),
            deletedAt: c.decodeISODateIfPresent(forKey: .deletedAt)
        )
    }

    func copyWith(
        id: String? = nil,
        date: Date? = nil,
        recipeId: String? = nil,
        recipeName: String? = nil,
        recipeImageUrl: String? = nil,
        servings: Int? = nil,
        done: Bool? = nil,
        title: String? = nil,
        mealType: String? = nil,
        isLeftover: Bool? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> MealPlanEntry {
        MealPlanEntry(
            id: id ?? self.id,
            date: date ?? self.date,
            recipeId: recipeId ?? self.recipeId,
            recipeName: recipeName ?? self.recipeName,
            recipeImageUrl: recipeImageUrl ?? self.recipeImageUrl,
            servings: servings ?? self.servings,
            done: done ?? self.done,
            title: title ?? self.title,
            mealType: mealType ?? self.mealType,
            isLeftover: isLeftover ?? self.isLeftover,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}
