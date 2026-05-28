class Household {
  const Household({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.defaultStorageArea,
    this.categoryPreferences = const {},
  });

  final String id;
  final String name;
  final String ownerId;
  final String defaultStorageArea;
  final Map<String, dynamic> categoryPreferences;

  factory Household.fromJson(Map<String, dynamic> json) {
    return Household(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      defaultStorageArea: json['default_storage_area'] as String? ?? 'fridge',
      categoryPreferences: json['category_preferences'] is Map
          ? Map<String, dynamic>.from(json['category_preferences'] as Map)
          : const {},
    );
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.householdId,
    required this.userId,
    required this.role,
    required this.email,
  });

  final String householdId;
  final String userId;
  final String role;
  final String email;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    return HouseholdMember(
      householdId: json['household_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      email: json['email'] as String? ?? '',
    );
  }
}

class HouseholdInvitePreview {
  const HouseholdInvitePreview({
    this.inviteId = '',
    required this.householdId,
    required this.householdName,
    required this.ownerEmail,
    required this.invitedEmail,
    required this.memberCount,
    required this.inventoryCount,
    required this.shoppingCount,
    required this.customRecipeCount,
    this.expiresAt,
  });

  final String inviteId;
  final String householdId;
  final String householdName;
  final String ownerEmail;
  final String invitedEmail;
  final int memberCount;
  final int inventoryCount;
  final int shoppingCount;
  final int customRecipeCount;
  final DateTime? expiresAt;

  factory HouseholdInvitePreview.fromJson(Map<String, dynamic> json) {
    return HouseholdInvitePreview(
      inviteId: json['invite_id'] as String? ?? '',
      householdId: json['household_id'] as String? ?? '',
      householdName: json['household_name'] as String? ?? '',
      ownerEmail: json['owner_email'] as String? ?? '',
      invitedEmail: json['invited_email'] as String? ?? '',
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      inventoryCount: (json['inventory_count'] as num?)?.toInt() ?? 0,
      shoppingCount: (json['shopping_count'] as num?)?.toInt() ?? 0,
      customRecipeCount: (json['custom_recipe_count'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }
}

class OwnerPendingInvite {
  const OwnerPendingInvite({
    required this.id,
    required this.email,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String email;
  final DateTime expiresAt;
  final DateTime createdAt;

  factory OwnerPendingInvite.fromJson(Map<String, dynamic> json) {
    return OwnerPendingInvite(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
