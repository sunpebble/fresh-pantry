import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/db/app_database.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';

void main() {
  test('saveRecipes then loadAllFor round-trips, skips blank id/name', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = CustomRecipeRepo(db);

    await repo.saveRecipes('hh-1', [
      Recipe(id: 'r1', name: 'Soup', ingredients: const [], steps: const []),
      Recipe(id: '', name: 'Blank', ingredients: const [], steps: const []),
    ]);

    final loaded = await repo.loadAllFor('hh-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'r1');

    await db.close();
  });
}
