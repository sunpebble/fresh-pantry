import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  group('customRecipesProvider', () {
    test('loads an empty list when no custom recipes are saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider), isEmpty);
    });

    test('adds a recipe and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).add(_recipe('r1'));

      expect(container.read(customRecipesProvider).single.name, '番茄炒蛋');
      final saved = await container
          .read(customRecipeRepoProvider)
          .loadAllFor('');
      expect(saved.single.id, 'r1');
    });

    test('concurrent adds do not lose recipes in state or storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
      );
      addTearDown(container.dispose);

      await Future.wait([
        container.read(customRecipesProvider.notifier).add(_recipe('r1')),
        container.read(customRecipesProvider.notifier).add(_recipe('r2')),
      ]);

      expect(container.read(customRecipesProvider).map((recipe) => recipe.id), [
        'r1',
        'r2',
      ]);
      final saved = await container
          .read(customRecipeRepoProvider)
          .loadAllFor('');
      expect(saved.map((recipe) => recipe.id), ['r1', 'r2']);
    });

    test(
      'adding an invalid recipe is a no-op and does not persist it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = newTestDatabase();
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
          ],
        );
        addTearDown(container.dispose);

        await container.read(customRecipesProvider.notifier).add(_recipe(''));
        await container
            .read(customRecipesProvider.notifier)
            .add(_recipe('r1').copyWith(name: ''));

        expect(container.read(customRecipesProvider), isEmpty);
        final saved = await container
            .read(customRecipeRepoProvider)
            .loadAllFor('');
        expect(saved, isEmpty);
      },
    );

    test('updates a recipe while preserving its id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            customRecipes: [_recipe('r1')],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(customRecipesProvider.notifier)
          .update('r1', _recipe('different').copyWith(name: '黑椒鸡胸'));

      final updated = container.read(customRecipesProvider).single;
      expect(updated.id, 'r1');
      expect(updated.name, '黑椒鸡胸');
    });

    test('removes a recipe and persists removal', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            customRecipes: [_recipe('r1')],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).remove('r1');

      expect(container.read(customRecipesProvider), isEmpty);
      final saved = await container
          .read(customRecipeRepoProvider)
          .loadAllFor('');
      expect(saved, isEmpty);
    });

    test('malformed saved row falls back to an empty list', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      // A row whose payload is not valid recipe JSON must be skipped on load
      // rather than crashing the read (the JSON-tolerance that used to live in
      // the notifier now lives in the repo's row decoder).
      await db
          .into(db.customRecipes)
          .insert(
            CustomRecipesCompanion.insert(
              id: 'r1',
              householdId: const Value(''),
              payloadJson: '{bad json',
            ),
          );

      final repo = CustomRecipeRepo(db);

      expect(await repo.loadAllFor(''), isEmpty);
    });

    test('loads valid recipes when persisted rows have bad rows', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      // Mix of: a valid recipe, a non-decodable row (the old `42` non-map
      // entry), and a partial-but-valid map missing optional fields.
      await db.batch((b) {
        b.insertAll(db.customRecipes, [
          CustomRecipesCompanion.insert(
            id: 'r1',
            householdId: const Value(''),
            payloadJson: jsonEncode(_recipe('r1').toJson()),
          ),
          CustomRecipesCompanion.insert(
            id: 'bad',
            householdId: const Value(''),
            payloadJson: '42',
          ),
          CustomRecipesCompanion.insert(
            id: 'r2',
            householdId: const Value(''),
            payloadJson: jsonEncode({'id': 'r2', 'name': '黑椒鸡胸'}),
          ),
        ]);
      });

      final repo = CustomRecipeRepo(db);

      expect((await repo.loadAllFor('')).map((recipe) => recipe.id), [
        'r1',
        'r2',
      ]);
    });
  });
}

Recipe _recipe(String id) {
  return Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '家常',
    difficulty: 1,
    cookingMinutes: 15,
    description: '快手家常菜',
    ingredients: [
      RecipeIngredient(name: '番茄', amount: '2个'),
      RecipeIngredient(name: '鸡蛋', amount: '2个'),
    ],
    steps: const ['切番茄', '炒鸡蛋', '合炒调味'],
  );
}
