import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/ingredient_identity.dart';
import 'package:fresh_pantry/models/storage_area.dart';

Ingredient _ing({
  required String name,
  String quantity = '1',
  String unit = '个',
  String? category,
  IconType storage = IconType.fridge,
}) => Ingredient(
  name: name,
  quantity: quantity,
  unit: unit,
  imageUrl: '',
  freshnessPercent: 1.0,
  state: FreshnessState.fresh,
  category: category,
  storage: storage,
);

void main() {
  group('IngredientIdentity.isPerishable', () {
    test('perishable category → true', () {
      expect(
        IngredientIdentity.isPerishable(
          category: FoodCategories.dairyAndEggs,
          name: '随便',
        ),
        isTrue,
      );
    });

    test('perishable by name even when category missing → true', () {
      expect(
        IngredientIdentity.isPerishable(category: null, name: '牛奶'),
        isTrue,
      );
    });

    test('non-perishable category and name → false', () {
      expect(
        IngredientIdentity.isPerishable(
          category: FoodCategories.other,
          name: '米',
        ),
        isFalse,
      );
    });
  });

  group('IngredientIdentity.resolveMergeTarget', () {
    test('non-perishable + name×unit×storage match + numeric qty → index', () {
      final inventory = [
        _ing(
          name: '米',
          quantity: '3',
          unit: 'kg',
          category: FoodCategories.other,
          storage: IconType.pantry,
        ),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
          inventory: inventory,
        ),
        0,
      );
    });

    test('perishable → -1 (always a new Batch)', () {
      final inventory = [
        _ing(name: '牛奶', unit: '盒', category: FoodCategories.dairyAndEggs),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '牛奶',
          unit: '盒',
          storage: IconType.fridge,
          category: FoodCategories.dairyAndEggs,
          inventory: inventory,
        ),
        -1,
      );
    });

    test('different unit → -1', () {
      final inventory = [
        _ing(name: '葱', unit: '把', category: FoodCategories.other),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '葱',
          unit: 'g',
          storage: IconType.fridge,
          category: FoodCategories.other,
          inventory: inventory,
        ),
        -1,
      );
    });

    test('different storage → -1', () {
      final inventory = [
        _ing(
          name: '苹果',
          unit: '个',
          category: FoodCategories.other,
          storage: IconType.fridge,
        ),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '苹果',
          unit: '个',
          storage: IconType.pantry,
          category: FoodCategories.other,
          inventory: inventory,
        ),
        -1,
      );
    });

    test('blank candidate name → -1', () {
      final inventory = [
        _ing(name: '', unit: '个', category: FoodCategories.other),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '   ',
          unit: '个',
          storage: IconType.fridge,
          category: FoodCategories.other,
          inventory: inventory,
        ),
        -1,
      );
    });

    test('no inventory → -1', () {
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
          inventory: const [],
        ),
        -1,
      );
    });

    // The drift this module exists to kill: the matching row holds a
    // non-numeric quantity, so merging would silently discard its stock. Both
    // proposal-time defaulting and apply-time re-resolution must refuse it.
    test('matching row with non-numeric quantity → -1', () {
      final inventory = [
        _ing(
          name: '盐',
          quantity: '适量',
          unit: 'g',
          category: FoodCategories.other,
          storage: IconType.pantry,
        ),
      ];
      expect(
        IngredientIdentity.resolveMergeTarget(
          name: '盐',
          unit: 'g',
          storage: IconType.pantry,
          category: FoodCategories.other,
          inventory: inventory,
        ),
        -1,
      );
    });
  });
}
