import Foundation

/// Core inventory item (one pantry/fridge row / batch). Backbone synced entity.
///
/// Full value equality over all fields incl. the sync triplet. `id == ""`
/// means local-only / never-synced — preserve that semantic for the gateway.
struct Ingredient: Equatable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var quantity: String
    var unit: String
    var imageUrl: String
    var freshnessPercent: Double
    var state: FreshnessState
    var expiryLabel: String?
    var category: String?
    var barcode: String?
    var storage: IconType
    var expiryDate: Date?
    var addedAt: Date?
    var shelfLifeDays: Int?
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

    init(
        id: String = "",
        name: String,
        quantity: String,
        unit: String,
        imageUrl: String,
        freshnessPercent: Double,
        state: FreshnessState,
        expiryLabel: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        storage: IconType = .fridge,
        expiryDate: Date? = nil,
        addedAt: Date? = nil,
        shelfLifeDays: Int? = nil,
        remoteVersion: Int = 0,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.imageUrl = imageUrl
        self.freshnessPercent = freshnessPercent
        self.state = state
        self.expiryLabel = expiryLabel
        self.category = category
        self.barcode = barcode
        self.storage = storage
        self.expiryDate = expiryDate
        self.addedAt = addedAt
        self.shelfLifeDays = shelfLifeDays
        self.remoteVersion = remoteVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, imageUrl, freshnessPercent, state
        case expiryLabel, category, barcode, storage, expiryDate, addedAt
        case shelfLifeDays, remoteVersion, clientUpdatedAt, deletedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(imageUrl, forKey: .imageUrl)
        try c.encode(freshnessPercent, forKey: .freshnessPercent)
        try c.encode(state.rawValue, forKey: .state)
        try c.encodeAlways(expiryLabel, forKey: .expiryLabel)
        try c.encodeAlways(category, forKey: .category)
        try c.encodeAlways(barcode, forKey: .barcode)
        try c.encode(storage.rawValue, forKey: .storage)
        try c.encodeISODateAlways(expiryDate, forKey: .expiryDate)
        try c.encodeISODateAlways(addedAt, forKey: .addedAt)
        try c.encodeAlways(shelfLifeDays, forKey: .shelfLifeDays)
        try c.encode(remoteVersion, forKey: .remoteVersion)
        try c.encodeISODateAlways(clientUpdatedAt, forKey: .clientUpdatedAt)
        try c.encodeISODateAlways(deletedAt, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientIfPresent(String.self, forKey: .id) ?? ""
        name = c.decodeLenientIfPresent(String.self, forKey: .name) ?? ""
        quantity = c.decodeLenientIfPresent(String.self, forKey: .quantity) ?? "1"
        unit = c.decodeLenientIfPresent(String.self, forKey: .unit) ?? "份"
        imageUrl = c.decodeLenientIfPresent(String.self, forKey: .imageUrl) ?? ""
        freshnessPercent = c.decodeDoubleIfPresent(forKey: .freshnessPercent) ?? 1.0
        state = FreshnessState.fromName(c.decodeLenientIfPresent(String.self, forKey: .state))
        expiryLabel = c.decodeLenientIfPresent(String.self, forKey: .expiryLabel)
        category = c.decodeLenientIfPresent(String.self, forKey: .category)
        barcode = c.decodeLenientIfPresent(String.self, forKey: .barcode)
        storage = IconType.fromName(c.decodeLenientIfPresent(String.self, forKey: .storage))
        expiryDate = c.decodeISODateIfPresent(forKey: .expiryDate)
        addedAt = c.decodeISODateIfPresent(forKey: .addedAt)
        shelfLifeDays = c.decodeIntIfPresent(forKey: .shelfLifeDays)
        remoteVersion = c.decodeIntIfPresent(forKey: .remoteVersion) ?? 0
        clientUpdatedAt = c.decodeISODateIfPresent(forKey: .clientUpdatedAt)
        deletedAt = c.decodeISODateIfPresent(forKey: .deletedAt)
    }

    func copyWith(
        id: String? = nil,
        name: String? = nil,
        quantity: String? = nil,
        unit: String? = nil,
        imageUrl: String? = nil,
        freshnessPercent: Double? = nil,
        state: FreshnessState? = nil,
        expiryLabel: String? = nil,
        category: String? = nil,
        barcode: String? = nil,
        storage: IconType? = nil,
        expiryDate: Date? = nil,
        addedAt: Date? = nil,
        shelfLifeDays: Int? = nil,
        remoteVersion: Int? = nil,
        clientUpdatedAt: Date? = nil,
        deletedAt: Date? = nil,
        clearClientUpdatedAt: Bool = false,
        clearDeletedAt: Bool = false
    ) -> Ingredient {
        Ingredient(
            id: id ?? self.id,
            name: name ?? self.name,
            quantity: quantity ?? self.quantity,
            unit: unit ?? self.unit,
            imageUrl: imageUrl ?? self.imageUrl,
            freshnessPercent: freshnessPercent ?? self.freshnessPercent,
            state: state ?? self.state,
            expiryLabel: expiryLabel ?? self.expiryLabel,
            category: category ?? self.category,
            barcode: barcode ?? self.barcode,
            storage: storage ?? self.storage,
            expiryDate: expiryDate ?? self.expiryDate,
            addedAt: addedAt ?? self.addedAt,
            shelfLifeDays: shelfLifeDays ?? self.shelfLifeDays,
            remoteVersion: remoteVersion ?? self.remoteVersion,
            clientUpdatedAt: clearClientUpdatedAt ? nil : (clientUpdatedAt ?? self.clientUpdatedAt),
            deletedAt: clearDeletedAt ? nil : (deletedAt ?? self.deletedAt)
        )
    }
}
