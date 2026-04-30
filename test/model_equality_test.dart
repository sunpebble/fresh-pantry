import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  test(
    'ingredients with the same name but different details are not equal',
    () {
      final first = _ingredient('番茄', quantity: '1');
      final second = _ingredient('番茄', quantity: '2');

      expect(first == second, isFalse);
      expect({first, second}, hasLength(2));
    },
  );

  test('scored recipes include expiring match count in equality', () {
    final recipe = Recipe(
      id: 'r1',
      name: '番茄炒蛋',
      category: '家常',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: const [],
      steps: const [],
    );
    final first = ScoredRecipe(
      recipe: recipe,
      score: 1,
      matchedCount: 2,
      expiringMatchedCount: 0,
    );
    final second = first.copyWith(expiringMatchedCount: 1);

    expect(first == second, isFalse);
    expect({first, second}, hasLength(2));
  });
}

Ingredient _ingredient(String name, {required String quantity}) {
  return Ingredient(
    name: name,
    quantity: quantity,
    unit: '个',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: '测试',
    storage: IconType.fridge,
  );
}
