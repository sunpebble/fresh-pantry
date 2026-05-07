import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  Ingredient buildIngredient({
    String name = '番茄',
    String quantity = '2',
    String unit = '个',
    String imageUrl = '',
    String? category = '蔬菜',
  }) {
    return Ingredient(
      name: name,
      quantity: quantity,
      unit: unit,
      imageUrl: imageUrl,
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
      category: category,
      storage: IconType.fridge,
    );
  }

  group('ShoppingItem.fromIngredient', () {
    test('maps name / detail / category from ingredient', () {
      final ingredient = buildIngredient();
      final item = ShoppingItem.fromIngredient(ingredient);

      expect(item.name, '番茄');
      expect(item.detail, '2 个');
      expect(item.category, '蔬菜');
      expect(item.id, isNotEmpty);
      expect(item.id, startsWith('si_'));
    });

    test('falls back to 其他 when ingredient has no category', () {
      final ingredient = buildIngredient(category: null);
      final item = ShoppingItem.fromIngredient(ingredient);

      expect(item.category, '其他');
    });

    test('uses ingredient imageUrl when non-empty', () {
      final ingredient = buildIngredient(
        imageUrl: 'https://example.com/tomato.png',
      );
      final item = ShoppingItem.fromIngredient(ingredient);

      expect(item.imageUrl, 'https://example.com/tomato.png');
    });

    test('imageUrl is null when ingredient imageUrl is empty', () {
      final ingredient = buildIngredient(imageUrl: '');
      final item = ShoppingItem.fromIngredient(ingredient);

      expect(item.imageUrl, isNull);
    });

    test('honors explicit id when provided', () {
      final ingredient = buildIngredient();
      final item = ShoppingItem.fromIngredient(ingredient, id: 'fixed_id');

      expect(item.id, 'fixed_id');
    });
  });
}
