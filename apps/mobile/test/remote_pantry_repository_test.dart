import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/sync/remote_pantry_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('inventoryRowFromJson maps Supabase row to domain map', () {
    final row = {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Milk',
      'quantity': '1',
      'unit': 'box',
      'image_url': '',
      'freshness_percent': 1,
      'state': 'fresh',
      'storage': 'fridge',
      'version': 2,
      'client_updated_at': '2026-05-27T00:00:00.000Z',
    };

    final mapped = inventoryRowFromJson(row);

    expect(mapped['id'], row['id']);
    expect(mapped['imageUrl'], '');
    expect(mapped['freshnessPercent'], 1.0);
    expect(mapped['remoteVersion'], 2);
    expect(mapped['clientUpdatedAt'], row['client_updated_at']);
  });

  test('inventoryRowForUpsert maps domain map to Supabase row', () {
    final row = inventoryRowForUpsert('household_1', const {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Milk',
      'quantity': '1',
      'unit': 'box',
      'imageUrl': '',
      'freshnessPercent': 1.0,
      'state': 'fresh',
      'storage': 'fridge',
      'remoteVersion': 2,
      'clientUpdatedAt': '2026-05-27T00:00:00.000Z',
    });

    expect(row['household_id'], 'household_1');
    expect(row['image_url'], '');
    expect(row['freshness_percent'], 1.0);
    expect(row['version'], 2);
    expect(row['client_updated_at'], '2026-05-27T00:00:00.000Z');
  });

  test('inventoryRowForUpsert uses version 1 for unsynced local rows', () {
    final missingVersion = inventoryRowForUpsert('household_1', const {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Milk',
      'quantity': '1',
      'unit': 'box',
    });
    final zeroVersion = inventoryRowForUpsert('household_1', const {
      'id': '22222222-2222-2222-2222-222222222222',
      'name': 'Eggs',
      'quantity': '6',
      'unit': 'pcs',
      'remoteVersion': 0,
    });

    expect(missingVersion['version'], 1);
    expect(zeroVersion['version'], 1);
  });

  test(
    'inventoryRowForUpsert omits invalid local ids so database uuid defaults apply',
    () {
      final emptyId = inventoryRowForUpsert('household_1', const {
        'id': '',
        'name': 'Milk',
        'quantity': '1',
        'unit': 'box',
      });
      final legacyId = inventoryRowForUpsert('household_1', const {
        'id': 'ai_123',
        'name': 'Eggs',
        'quantity': '6',
        'unit': 'pcs',
      });

      expect(emptyId.containsKey('id'), isFalse);
      expect(legacyId.containsKey('id'), isFalse);
    },
  );

  test('inventoryRowForUpsert supplies not-null schema defaults', () {
    final row = inventoryRowForUpsert('household_1', const {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Milk',
      'quantity': '1',
      'unit': 'box',
    });

    expect(row['image_url'], '');
    expect(row['freshness_percent'], 1.0);
    expect(row['state'], 'fresh');
    expect(row['storage'], 'fridge');
  });

  test(
    'SupabaseRemotePantryRepository rejects versioned inventory upserts',
    () async {
      final repository = SupabaseRemotePantryRepository(
        SupabaseClient('https://example.supabase.co', 'publishable'),
      );

      await expectLater(
        repository.upsertInventory('household_1', const [
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'name': 'Milk',
            'quantity': '1',
            'unit': 'box',
            'remoteVersion': 2,
          },
        ]),
        throwsArgumentError,
      );
    },
  );

  test('Household.fromJson maps Supabase household fields', () {
    final household = Household.fromJson(const {
      'id': 'household_1',
      'name': 'Home',
      'owner_id': 'user_1',
      'default_storage_area': 'pantry',
    });

    expect(household.id, 'household_1');
    expect(household.name, 'Home');
    expect(household.ownerId, 'user_1');
    expect(household.defaultStorageArea, 'pantry');
  });
}
