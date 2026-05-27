class Household {
  const Household({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.defaultStorageArea,
  });

  final String id;
  final String name;
  final String ownerId;
  final String defaultStorageArea;

  factory Household.fromJson(Map<String, dynamic> json) {
    return Household(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      defaultStorageArea: json['default_storage_area'] as String? ?? 'fridge',
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
