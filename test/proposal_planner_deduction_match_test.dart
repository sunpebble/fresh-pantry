import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/proposal_planner.dart';

Ingredient _ing({required String name, String qty = '1', DateTime? expiry}) =>
    Ingredient(
      name: name,
      quantity: qty,
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.fridge,
      expiryDate: expiry,
      addedAt: DateTime(2026, 5, 1),
    );

void main() {
  test('returns matching inventory rows sorted by earliest expiry', () {
    final inventory = [
      _ing(name: '葱', qty: '1', expiry: DateTime(2026, 5, 30)), // index 0
      _ing(name: '香葱', qty: '1', expiry: DateTime(2026, 5, 20)), // index 1
      _ing(name: '盐', qty: '1'), // index 2 (no match)
    ];
    final matches = ProposalPlanner.fuzzyMatchInventoryRows('葱', inventory);
    expect(matches.map((m) => m.inventoryRowIndex).toList(), [1, 0]);
  });

  test('no match → empty list', () {
    final inventory = [_ing(name: '盐', qty: '1')];
    expect(ProposalPlanner.fuzzyMatchInventoryRows('葱', inventory), isEmpty);
  });

  test('blank inventory names do not match every recipe ingredient', () {
    final inventory = [_ing(name: '', qty: '1')];
    expect(ProposalPlanner.fuzzyMatchInventoryRows('葱', inventory), isEmpty);
  });

  test('substring containment in either direction', () {
    final inventory = [_ing(name: '猪肉末', qty: '1')];
    expect(
      ProposalPlanner.fuzzyMatchInventoryRows('猪肉', inventory),
      isNotEmpty,
    );
    expect(ProposalPlanner.fuzzyMatchInventoryRows('肉', inventory), isNotEmpty);
  });
}
