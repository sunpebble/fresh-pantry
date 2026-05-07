import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  test('IngredientDraft.selected defaults to true', () {
    final d = IngredientDraft(
      id: 'd1',
      name: DraftField.ai('番茄'),
      quantity: DraftField.ai('3'),
      unit: DraftField.ai('个'),
      category: DraftField.ai('蔬菜'),
      storage: DraftField.ai(IconType.fridge),
      shelfLifeDays: DraftField.ai(7),
    );
    expect(d.selected, true);
  });

  test('toIngredient preserves the captured fields', () {
    final d = IngredientDraft(
      id: 'd1',
      name: DraftField.ai('番茄'),
      quantity: DraftField.ai('3'),
      unit: DraftField.ai('个'),
      category: DraftField.ai('蔬菜'),
      storage: DraftField.ai(IconType.fridge),
      shelfLifeDays: DraftField.ai(7),
    );
    final ing = d.toIngredient();
    expect(ing.name, '番茄');
    expect(ing.quantity, '3');
    expect(ing.unit, '个');
    expect(ing.storage, IconType.fridge);
    expect(ing.shelfLifeDays, 7);
  });
}
