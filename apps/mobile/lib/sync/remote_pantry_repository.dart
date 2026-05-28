import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config.dart';
import '../household/invite_token.dart';
import '../household/household_models.dart';

Map<String, dynamic> inventoryRowFromJson(Map<String, dynamic> row) {
  return {
    'id': row['id'],
    'name': row['name'],
    'quantity': row['quantity'],
    'unit': row['unit'],
    'imageUrl': row['image_url'] ?? '',
    'freshnessPercent': (row['freshness_percent'] as num?)?.toDouble() ?? 1.0,
    'state': row['state'] ?? 'fresh',
    'expiryLabel': row['expiry_label'],
    'category': row['category'],
    'barcode': row['barcode'],
    'storage': row['storage'],
    'expiryDate': row['expiry_date'],
    'addedAt': row['added_at'],
    'shelfLifeDays': row['shelf_life_days'],
    'remoteVersion': (row['version'] as num?)?.toInt() ?? 0,
    'clientUpdatedAt': row['client_updated_at'],
    'deletedAt': row['deleted_at'],
  };
}

Map<String, dynamic> shoppingRowFromJson(Map<String, dynamic> row) {
  return {
    'id': row['id'],
    'name': row['name'],
    'detail': row['detail'] ?? '',
    'imageUrl': row['image_url'],
    'category': row['category'] ?? '其他',
    'isChecked': row['is_checked'] ?? false,
    'remoteVersion': (row['version'] as num?)?.toInt() ?? 0,
    'clientUpdatedAt': row['client_updated_at'],
    'deletedAt': row['deleted_at'],
  };
}

Map<String, dynamic> customRecipeRowFromJson(Map<String, dynamic> row) {
  final payload = row['payload'];
  final recipe = payload is Map
      ? Map<String, dynamic>.from(payload)
      : <String, dynamic>{};
  return {
    ...recipe,
    'id': row['id'] ?? recipe['id'],
    'remoteVersion': (row['version'] as num?)?.toInt() ?? 0,
    'clientUpdatedAt': row['client_updated_at'],
    'deletedAt': row['deleted_at'],
  };
}

Map<String, dynamic> inventoryRowForUpsert(
  String householdId,
  Map<String, dynamic> item,
) {
  final row = {
    'household_id': householdId,
    'name': item['name'],
    'quantity': item['quantity'],
    'unit': item['unit'],
    'image_url': item['imageUrl'] ?? '',
    'freshness_percent': item['freshnessPercent'] ?? 1.0,
    'state': item['state'] ?? 'fresh',
    'expiry_label': item['expiryLabel'],
    'category': item['category'],
    'barcode': item['barcode'],
    'storage': item['storage'] ?? 'fridge',
    'expiry_date': item['expiryDate'],
    'added_at': item['addedAt'],
    'shelf_life_days': item['shelfLifeDays'],
    'version': _versionForUpsert(item['remoteVersion']),
    'client_updated_at': item['clientUpdatedAt'],
    'deleted_at': item['deletedAt'],
  };
  final id = item['id'];
  if (id is String && _isUuid(id)) {
    row['id'] = id;
  }
  return row;
}

Map<String, dynamic> shoppingRowForUpsert(
  String householdId,
  Map<String, dynamic> item,
) {
  final row = {
    'household_id': householdId,
    'name': item['name'],
    'detail': item['detail'] ?? '',
    'image_url': item['imageUrl'],
    'category': item['category'] ?? '其他',
    'is_checked': item['isChecked'] ?? false,
    'version': _versionForUpsert(item['remoteVersion']),
    'client_updated_at': item['clientUpdatedAt'],
    'deleted_at': item['deletedAt'],
  };
  final id = item['id'];
  if (id is String && _isUuid(id)) {
    row['id'] = id;
  }
  return row;
}

Map<String, dynamic> customRecipeRowForUpsert(
  String householdId,
  Map<String, dynamic> recipe,
) {
  final row = {
    'household_id': householdId,
    'payload': recipe,
    'version': _versionForUpsert(recipe['remoteVersion']),
    'client_updated_at': recipe['clientUpdatedAt'],
    'deleted_at': recipe['deletedAt'],
  };
  final id = recipe['id'];
  if (id is String && _isUuid(id)) {
    row['id'] = id;
  }
  return row;
}

int _versionForUpsert(Object? remoteVersion) {
  final version = remoteVersion is num ? remoteVersion.toInt() : 0;
  return version <= 0 ? 1 : version;
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

abstract class RemotePantryRepository {
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<String> createInvite({required String householdId, String? email});
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId);
  Future<List<HouseholdInvitePreview>> loadPendingInvites();
  Future<HouseholdInvitePreview> previewInvite(String token);
  Future<void> acceptInvite(String token);
  Future<void> acceptInviteById(String inviteId);
  Future<void> removeMember(String targetUserId);
  Future<void> revokeInvite(String inviteId);
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
  Future<void> updateHouseholdName(String householdId, String name);
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  );
  Future<List<Map<String, dynamic>>> loadInventory(String householdId);
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId);
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId);
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId);
}

class SupabaseRemotePantryRepository implements RemotePantryRepository {
  SupabaseRemotePantryRepository(
    this._client, {
    String apiBaseUrl = defaultFreshPantryApiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl;

  final SupabaseClient _client;
  final String _apiBaseUrl;

  @override
  Future<List<Household>> loadHouseholds() async {
    final rows = await _client.from('households').select();
    return rows.map(Household.fromJson).toList();
  }

  @override
  Future<Household> createHousehold(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create household without a signed-in user.');
    }

    final row = {
      'id': const Uuid().v4(),
      'name': name,
      'owner_id': userId,
      'default_storage_area': 'fridge',
    };
    await _client.from('households').insert(row);
    await _client.from('household_members').insert({
      'household_id': row['id'],
      'user_id': userId,
      'role': 'owner',
    });
    return Household.fromJson(row);
  }

  @override
  Future<String> createInvite({
    required String householdId,
    String? email,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create invite without a signed-in user.');
    }

    final trimmedEmail = email?.trim();
    final targetEmail = trimmedEmail == null || trimmedEmail.isEmpty
        ? null
        : trimmedEmail;

    final token = generateInviteToken();
    await _client.from('household_invites').insert({
      'household_id': householdId,
      'email': targetEmail,
      'token_hash': hashInviteToken(token),
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 14))
          .toIso8601String(),
      'created_by': userId,
    });
    final baseUrl = _apiBaseUrl.endsWith('/')
        ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
        : _apiBaseUrl;
    return '$baseUrl/invite/$token';
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) return const [];
    if (_client.auth.currentUser == null) {
      throw StateError(
        'Cannot list household members without a signed-in user.',
      );
    }

    final rows = await _client.rpc(
      'list_household_members',
      params: {'target_household_id': trimmedHouseholdId},
    );
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => HouseholdMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot list pending invites without a signed-in user.');
    }

    final rows = await _client.rpc('list_pending_household_invites');
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map(
          (row) =>
              HouseholdInvitePreview.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    final trimmedToken = token.trim();
    if (!isInviteTokenShapeValid(trimmedToken)) {
      throw ArgumentError.value(token, 'token', 'Invalid invite token');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot preview invite without a signed-in user.');
    }

    final rows = await _client.rpc(
      'preview_household_invite',
      params: {'invite_token_hash': hashInviteToken(trimmedToken)},
    );
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('Invite preview is not available.');
    }

    return HouseholdInvitePreview.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<void> acceptInvite(String token) async {
    final trimmedToken = token.trim();
    if (!isInviteTokenShapeValid(trimmedToken)) {
      throw ArgumentError.value(token, 'token', 'Invalid invite token');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot accept invite without a signed-in user.');
    }

    await _client.rpc(
      'accept_household_invite',
      params: {'invite_token_hash': hashInviteToken(trimmedToken)},
    );
  }

  @override
  Future<void> acceptInviteById(String inviteId) async {
    final trimmedInviteId = inviteId.trim();
    if (!_isUuid(trimmedInviteId)) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Invalid invite id');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot accept invite without a signed-in user.');
    }

    await _client.rpc(
      'accept_household_invite_by_id',
      params: {'target_invite_id': trimmedInviteId},
    );
  }

  @override
  Future<void> removeMember(String targetUserId) async {
    final trimmedUserId = targetUserId.trim();
    if (!_isUuid(trimmedUserId)) {
      throw ArgumentError.value(
        targetUserId,
        'targetUserId',
        'Invalid user id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot remove member without a signed-in user.');
    }

    await _client.rpc(
      'remove_household_member',
      params: {'target_user_id': trimmedUserId},
    );
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    final trimmedInviteId = inviteId.trim();
    if (!_isUuid(trimmedInviteId)) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Invalid invite id');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot revoke invite without a signed-in user.');
    }

    await _client.rpc(
      'revoke_household_invite',
      params: {'target_invite_id': trimmedInviteId},
    );
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) return const [];
    if (_client.auth.currentUser == null) {
      throw StateError(
        'Cannot list owner pending invites without a signed-in user.',
      );
    }

    final rows = await _client.rpc(
      'list_owner_pending_invites',
      params: {'target_household_id': trimmedHouseholdId},
    );
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map(
          (row) => OwnerPendingInvite.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateHouseholdName(String householdId, String name) async {
    final trimmedId = householdId.trim();
    if (!_isUuid(trimmedId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Household name cannot be empty');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot update household without a signed-in user.');
    }

    await _client
        .from('households')
        .update({'name': trimmedName})
        .eq('id', trimmedId);
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) async {
    final trimmedId = householdId.trim();
    if (!_isUuid(trimmedId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot update preferences without a signed-in user.');
    }

    await _client
        .from('households')
        .update({'category_preferences': preferences})
        .eq('id', trimmedId);
  }

  @override
  Future<List<Map<String, dynamic>>> loadInventory(String householdId) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    return rows.map(inventoryRowFromJson).toList();
  }

  @override
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertInventory only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('inventory_items')
        .upsert(
          rows.map((row) => inventoryRowForUpsert(householdId, row)).toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertShopping only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('shopping_items')
        .upsert(
          rows.map((row) => shoppingRowForUpsert(householdId, row)).toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertCustomRecipes only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('custom_recipes')
        .upsert(
          rows
              .map((row) => customRecipeRowForUpsert(householdId, row))
              .toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId) {
    return _client
        .from('inventory_items')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map((rows) => rows.map(inventoryRowFromJson).toList(growable: false));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId) {
    return _client
        .from('shopping_items')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map((rows) => rows.map(shoppingRowFromJson).toList(growable: false));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId) {
    return _client
        .from('custom_recipes')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map(
          (rows) => rows.map(customRecipeRowFromJson).toList(growable: false),
        );
  }
}

bool _hasRemoteVersion(Map<String, dynamic> row) {
  final version = row['remoteVersion'];
  return version is num && version.toInt() > 0;
}
