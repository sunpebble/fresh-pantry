import Foundation

/// Household-domain DTOs decoded from Supabase RPC responses. Ported from
/// `lib/household/household_models.dart` — each struct mirrors the Flutter
/// `fromJson` factory byte-for-byte (snake_case keys, the same null-coalescing
/// defaults, the same tolerant-vs-throwing date handling) so the Swift and
/// Flutter clients decode identical backend payloads without divergence.
///
/// Parity note on dates: the Flutter models are deliberately *asymmetric* —
/// `HouseholdInvitePreview.expiresAt` uses `DateTime.tryParse` (blank / absent /
/// unparseable -> null), while `OwnerPendingInvite` uses `DateTime.parse`
/// (throws on absent / unparseable). We reproduce both behaviors exactly: the
/// preview date is tolerant, the owner-invite dates are required.

/// A household row (`households` table). All fields null-coalesce to a default,
/// mirroring the Flutter `Household.fromJson` so a sparse response still decodes.
struct Household: Equatable, Sendable, Codable {
    var id: String
    var name: String
    var ownerId: String
    var defaultStorageArea: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case defaultStorageArea = "default_storage_area"
    }

    init(
        id: String = "",
        name: String = "",
        ownerId: String = "",
        defaultStorageArea: String = "fridge"
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.defaultStorageArea = defaultStorageArea
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            name: c.decodeLenientIfPresent(String.self, forKey: .name) ?? "",
            ownerId: c.decodeLenientIfPresent(String.self, forKey: .ownerId) ?? "",
            defaultStorageArea: c.decodeLenientIfPresent(String.self, forKey: .defaultStorageArea)
                ?? "fridge"
        )
    }
}

/// A member row from the `list_household_members` RPC. `role` defaults to
/// `member`; the profile fields default to "" (未设置) to match the Flutter
/// factory's tolerant decode.
struct HouseholdMember: Equatable, Sendable, Codable {
    var householdId: String
    var userId: String
    var role: String
    var email: String
    var displayName: String
    var nickname: String
    var avatarPath: String

    private enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case userId = "user_id"
        case role
        case email
        case displayName = "display_name"
        case nickname
        case avatarPath = "avatar_path"
    }

    init(
        householdId: String = "",
        userId: String = "",
        role: String = "member",
        email: String = "",
        displayName: String = "",
        nickname: String = "",
        avatarPath: String = ""
    ) {
        self.householdId = householdId
        self.userId = userId
        self.role = role
        self.email = email
        self.displayName = displayName
        self.nickname = nickname
        self.avatarPath = avatarPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            householdId: c.decodeLenientIfPresent(String.self, forKey: .householdId) ?? "",
            userId: c.decodeLenientIfPresent(String.self, forKey: .userId) ?? "",
            role: c.decodeLenientIfPresent(String.self, forKey: .role) ?? "member",
            email: c.decodeLenientIfPresent(String.self, forKey: .email) ?? "",
            displayName: c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? "",
            nickname: c.decodeLenientIfPresent(String.self, forKey: .nickname) ?? "",
            avatarPath: c.decodeLenientIfPresent(String.self, forKey: .avatarPath) ?? ""
        )
    }

    /// Display label: nickname → display_name → email → "成员".
    var resolvedName: String {
        if !nickname.isEmpty { return nickname }
        if !displayName.isEmpty { return displayName }
        if !email.isEmpty { return email }
        return String(localized: "household.member.fallback")
    }
}

/// Invite preview from `preview_household_invite` / `list_pending_household_invites`.
/// `inviteId` may be absent in the preview shape (only present in the list shape),
/// so it defaults to `''`. `expiresAt` is tolerant — `DateTime.tryParse` in the
/// Flutter factory yields null for blank / absent / unparseable.
struct HouseholdInvitePreview: Equatable, Sendable, Codable {
    var inviteId: String
    var householdId: String
    var householdName: String
    var ownerEmail: String
    var invitedEmail: String
    var memberCount: Int
    var inventoryCount: Int
    var shoppingCount: Int
    var customRecipeCount: Int
    var expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case householdId = "household_id"
        case householdName = "household_name"
        case ownerEmail = "owner_email"
        case invitedEmail = "invited_email"
        case memberCount = "member_count"
        case inventoryCount = "inventory_count"
        case shoppingCount = "shopping_count"
        case customRecipeCount = "custom_recipe_count"
        case expiresAt = "expires_at"
    }

    init(
        inviteId: String = "",
        householdId: String = "",
        householdName: String = "",
        ownerEmail: String = "",
        invitedEmail: String = "",
        memberCount: Int = 0,
        inventoryCount: Int = 0,
        shoppingCount: Int = 0,
        customRecipeCount: Int = 0,
        expiresAt: Date? = nil
    ) {
        self.inviteId = inviteId
        self.householdId = householdId
        self.householdName = householdName
        self.ownerEmail = ownerEmail
        self.invitedEmail = invitedEmail
        self.memberCount = memberCount
        self.inventoryCount = inventoryCount
        self.shoppingCount = shoppingCount
        self.customRecipeCount = customRecipeCount
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inviteId: c.decodeLenientIfPresent(String.self, forKey: .inviteId) ?? "",
            householdId: c.decodeLenientIfPresent(String.self, forKey: .householdId) ?? "",
            householdName: c.decodeLenientIfPresent(String.self, forKey: .householdName) ?? "",
            ownerEmail: c.decodeLenientIfPresent(String.self, forKey: .ownerEmail) ?? "",
            invitedEmail: c.decodeLenientIfPresent(String.self, forKey: .invitedEmail) ?? "",
            // Counts are `(num?)?.toInt() ?? 0` in Dart — tolerant of int/double.
            memberCount: c.decodeIntIfPresent(forKey: .memberCount) ?? 0,
            inventoryCount: c.decodeIntIfPresent(forKey: .inventoryCount) ?? 0,
            shoppingCount: c.decodeIntIfPresent(forKey: .shoppingCount) ?? 0,
            customRecipeCount: c.decodeIntIfPresent(forKey: .customRecipeCount) ?? 0,
            // `DateTime.tryParse(... ?? '')`: blank / absent / unparseable -> nil.
            expiresAt: c.decodeISODateIfPresent(forKey: .expiresAt)
        )
    }
}

/// A pending invite the current user owns, from `list_owner_pending_invites`.
/// Unlike the other DTOs, the Flutter factory parses both dates with the
/// throwing `DateTime.parse`, so an absent / unparseable `expires_at` or
/// `created_at` is a decode error here — not a silent default.
struct OwnerPendingInvite: Equatable, Sendable, Codable {
    var id: String
    var email: String
    var expiresAt: Date
    var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    init(id: String = "", email: String = "", expiresAt: Date, createdAt: Date) {
        self.id = id
        self.email = email
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            email: c.decodeLenientIfPresent(String.self, forKey: .email) ?? "",
            // Required: mirror Dart's `DateTime.parse`, which throws on a missing
            // or unparseable value rather than null-coalescing.
            expiresAt: try OwnerPendingInvite.requiredDate(c, .expiresAt),
            createdAt: try OwnerPendingInvite.requiredDate(c, .createdAt)
        )
    }

    private static func requiredDate(
        _ c: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Date {
        guard let raw = c.decodeLenientIfPresent(String.self, forKey: key),
              let date = JSONDate.parse(raw)
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: c.codingPath + [key],
                    debugDescription: "Missing or unparseable required date for \(key.stringValue)"
                )
            )
        }
        return date
    }
}
