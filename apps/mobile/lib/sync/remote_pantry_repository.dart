import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
}

class SupabaseRemotePantryRepository implements RemotePantryRepository {
  SupabaseRemotePantryRepository(this._client);

  final SupabaseClient _client;

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
}

bool _hasRemoteVersion(Map<String, dynamic> row) {
  final version = row['remoteVersion'];
  return version is num && version.toInt() > 0;
}
