import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/proposal_planner.dart';

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
  group('ProposalPlanner.computeIntakeDefaultAction', () {
    test('non-perishable + name+unit+storage match → mergeInto', () {
      final inventory = [
        _ing(
          name: '米',
          unit: 'kg',
          category: FoodCategories.other,
          storage: IconType.pantry,
        ),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.mergeInto);
      expect(action.targetIndex, 0);
    });

    test('perishable + match → newRow (default to new Batch)', () {
      final inventory = [
        _ing(name: '牛奶', unit: '盒', category: FoodCategories.dairyAndEggs),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '牛奶',
          unit: '盒',
          storage: IconType.fridge,
          category: FoodCategories.dairyAndEggs,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
      expect(action.targetIndex, isNull);
    });

    test('different unit → newRow (no merge across units)', () {
      final inventory = [
        _ing(name: '葱', unit: '把', category: FoodCategories.other),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '葱',
          unit: 'g',
          storage: IconType.fridge,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
    });

    test('different storage → newRow', () {
      final inventory = [
        _ing(
          name: '苹果',
          unit: '个',
          category: FoodCategories.other,
          storage: IconType.fridge,
        ),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '苹果',
          unit: '个',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );
      expect(action.kind, IntakeAction.newRow);
    });

    test('no inventory → newRow', () {
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '米',
          unit: 'kg',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: const [],
      );
      expect(action.kind, IntakeAction.newRow);
    });

    test('blank candidate names never merge into blank inventory rows', () {
      final inventory = [
        _ing(
          name: '',
          unit: '个',
          category: FoodCategories.other,
          storage: IconType.pantry,
        ),
      ];
      final action = ProposalPlanner.computeIntakeDefaultAction(
        candidate: _IntakeCandidate(
          name: '   ',
          unit: '个',
          storage: IconType.pantry,
          category: FoodCategories.other,
        ),
        inventory: inventory,
      );

      expect(action.kind, IntakeAction.newRow);
      expect(action.targetIndex, isNull);
    });
  });
}

class _IntakeCandidate implements IntakeCandidate {
  _IntakeCandidate({
    required this.name,
    required this.unit,
    required this.storage,
    required this.category,
  });
  @override
  final String name;
  @override
  final String unit;
  @override
  final IconType storage;
  @override
  final String? category;
}
