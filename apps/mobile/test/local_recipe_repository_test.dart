import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/storage/local_recipe_repository.dart';

void main() {
  Recipe recipe(String id) => Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '素菜',
    difficulty: 1,
    cookingMinutes: 15,
    description: '',
    ingredients: [RecipeIngredient(name: '番茄')],
    steps: const ['炒'],
  );

  test('loadAll 解析 asset json 为 Recipe 列表', () async {
    final json = jsonEncode([recipe('howtocook:vegetable_dish/番茄炒蛋').toJson()]);
    final repo = LocalRecipeRepository(loadString: (_) async => json);

    final recipes = await repo.loadAll();

    expect(recipes.single.id, 'howtocook:vegetable_dish/番茄炒蛋');
    expect(recipes.single.name, '番茄炒蛋');
  });

  test('loadAll 缓存结果，第二次不再读 asset', () async {
    var calls = 0;
    final json = jsonEncode([recipe('a').toJson()]);
    final repo = LocalRecipeRepository(
      loadString: (_) async {
        calls++;
        return json;
      },
    );

    await repo.loadAll();
    await repo.loadAll();

    expect(calls, 1);
  });

  test('asset 不是 JSON 数组时抛异常（让上层转 fetchFailed）', () async {
    final repo = LocalRecipeRepository(loadString: (_) async => '{}');
    expect(repo.loadAll(), throwsFormatException);
  });

  test('loadAll 跳过坏条目，保留可解析的', () async {
    // Recipe.fromJson is lenient on Map entries (uses `as String? ?? ''`
    // default-fills), so it does not throw on a malformed map. The skip path
    // is therefore exercised by the non-Map element (42) being filtered out
    // by whereType<Map<String, dynamic>>(); the try/catch guard is still
    // correct defensive code for any future stricter validation.
    final validRecipeJson = recipe('howtocook:good').toJson();
    final raw = jsonEncode([validRecipeJson, 42]);
    final repo = LocalRecipeRepository(loadString: (_) async => raw);

    final recipes = await repo.loadAll();

    expect(recipes, hasLength(1));
    expect(recipes.single.id, 'howtocook:good');
  });
}
