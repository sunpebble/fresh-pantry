import Foundation

/// Shopping-list entry; convertible from an Ingredient.
/// Identity (Hashable/Equatable) is by `id` ONLY — matching the Flutter model.
struct ShoppingItem: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var detail: String
    var imageUrl: String?
    var category: String
    var isChecked: Bool
    var remoteVersion: Int
    var clientUpdatedAt: Date?
    var deletedAt: Date?

    init(
        id: String,
        name: String,
        detail: String,
        imageUrl: String? = nil,
        category: String,
        isChecked: Bool = false,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.imageUrl = imageUrl
        self.category = category
        self.isChecked = isChecked
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    /// A fresh lowercased UUID — a SYNC-CLEAN id. The household sync engine
    /// reconciles rows by id and writes only a UUID id remotely (`applyLocalId`),
    /// so a non-UUID local id (the old `si_<ms>`) would get a server-generated
    /// UUID on upload and then re-appear as a duplicate local-only row.
    static func newId() -> String { UUID().uuidString.lowercased() }

    /// Build a ShoppingItem from an Ingredient (mirrors `fromIngredient`).
    static func fromIngredient(_ ingredient: Ingredient, id: String? = nil) -> ShoppingItem {
        ShoppingItem(
            id: id ?? newId(),
            name: ingredient.name,
            detail: "\(ingredient.quantity) \(ingredient.unit)",
            imageUrl: ingredient.imageUrl.isEmpty ? nil : ingredient.imageUrl,
            category: ingredient.category ?? FoodCategories.other
        )
    }

    static func == (lhs: ShoppingItem, rhs: ShoppingItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id, name, detail, imageUrl, category, isChecked
        case remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(detail, forKey: .detail)
        try c.encodeAlways(imageUrl, forKey: .imageUrl)
        try c.encode(category, forKey: .category)
        try c.encode(isChecked, forKey: .isChecked)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientIfPresent(String.self, forKey: .id) ?? ""
        name = c.decodeLenientIfPresent(String.self, forKey: .name) ?? ""
        detail = c.decodeLenientIfPresent(String.self, forKey: .detail) ?? ""
        imageUrl = c.decodeLenientIfPresent(String.self, forKey: .imageUrl)
        category = c.decodeLenientIfPresent(String.self, forKey: .category) ?? FoodCategories.other
        isChecked = c.decodeLenientIfPresent(Bool.self, forKey: .isChecked) ?? false
        remoteVersion = c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0
        clientUpdatedAt = c.decodeISODateIfPresent(forKey: .clientUpdatedAt)
        deletedAt = c.decodeISODateIfPresent(forKey: .deletedAt)
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        detail: String? = nil,
        imageUrl: String? = nil,
        category: String? = nil,
        isChecked: Bool? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> ShoppingItem {
        ShoppingItem(
            id: id ?? self.id,
            name: name ?? self.name,
            detail: detail ?? self.detail,
            imageUrl: imageUrl ?? self.imageUrl,
            category: category ?? self.category,
            isChecked: isChecked ?? self.isChecked,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}

extension ShoppingItem {
    var displayName: String { FoodKnowledge.displayName(name) }
}

extension Date {
    /// Current epoch milliseconds — matches Dart `millisecondsSinceEpoch` ids.
    static var nowMilliseconds: Int { Int(Date().timeIntervalSince1970 * 1000) }
}
