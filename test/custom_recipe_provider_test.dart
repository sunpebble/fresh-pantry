import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('customRecipesProvider', () {
    test('loads an empty list when no custom recipes are saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider), isEmpty);
    });

    test('adds a recipe and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).add(_recipe('r1'));

      expect(container.read(customRecipesProvider).single.name, '番茄炒蛋');
      final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
      expect(saved, isA<List<dynamic>>());
      expect(saved.single['id'], 'r1');
    });

    test('concurrent adds do not lose recipes in state or storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
      final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
      expect(saved.map((recipe) => recipe['id']), ['r1', 'r2']);
    });

    test(
      'adding an invalid recipe is a no-op and does not persist it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await container.read(customRecipesProvider.notifier).add(_recipe(''));
        await container
            .read(customRecipesProvider.notifier)
            .add(_recipe('r1').copyWith(name: ''));

        expect(container.read(customRecipesProvider), isEmpty);
        expect(prefs.getString(customRecipesStorageKey), isNull);
      },
    );

    test('updates a recipe while preserving its id', () async {
      SharedPreferences.setMockInitialValues({
        customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
      SharedPreferences.setMockInitialValues({
        customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(customRecipesProvider.notifier).remove('r1');

      expect(container.read(customRecipesProvider), isEmpty);
      expect(json.decode(prefs.getString(customRecipesStorageKey)!), isEmpty);
    });

    test('malformed saved JSON falls back to an empty list', () async {
      SharedPreferences.setMockInitialValues({
        customRecipesStorageKey: '{bad json',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider), isEmpty);
    });

    test('loads valid recipes when persisted list has bad rows', () async {
      SharedPreferences.setMockInitialValues({
        customRecipesStorageKey: json.encode([
          _recipe('r1').toJson(),
          42,
          {'id': 'r2', 'name': '黑椒鸡胸'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(customRecipesProvider).map((recipe) => recipe.id), [
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
    ingredients: const [
      RecipeIngredient(name: '番茄', amount: '2个'),
      RecipeIngredient(name: '鸡蛋', amount: '2个'),
    ],
    steps: const ['切番茄', '炒鸡蛋', '合炒调味'],
  );
}
