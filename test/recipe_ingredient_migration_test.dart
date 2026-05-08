import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';

void main() {
  group('RecipeIngredient migration', () {
    test('reads new shape (quantity + unit) from json', () {
      final ing = RecipeIngredient.fromJson({
        'name': '西红柿',
        'quantity': '200',
        'unit': 'g',
        'amount': '200g',
      });
      expect(ing.name, '西红柿');
      expect(ing.quantity, '200');
      expect(ing.unit, 'g');
      expect(ing.amount, '200g');
    });

    test('parses legacy amount "200g" into quantity + unit', () {
      final ing = RecipeIngredient.fromJson({
        'name': '西红柿',
        'amount': '200g',
      });
      expect(ing.quantity, '200');
      expect(ing.unit, 'g');
      expect(ing.amount, '200g');
    });

    test('parses legacy amount "3 个" into quantity + unit', () {
      final ing = RecipeIngredient.fromJson({
        'name': '鸡蛋',
        'amount': '3 个',
      });
      expect(ing.quantity, '3');
      expect(ing.unit, '个');
    });

    test('parses legacy amount "1.5kg" with decimal', () {
      final ing = RecipeIngredient.fromJson({
        'name': '面粉',
        'amount': '1.5kg',
      });
      expect(ing.quantity, '1.5');
      expect(ing.unit, 'kg');
    });

    test('falls back to unit-only when amount has no leading number', () {
      final ing = RecipeIngredient.fromJson({
        'name': '盐',
        'amount': '适量',
      });
      expect(ing.quantity, '');
      expect(ing.unit, '适量');
    });

    test('handles empty amount gracefully', () {
      final ing = RecipeIngredient.fromJson({'name': '葱', 'amount': ''});
      expect(ing.quantity, '');
      expect(ing.unit, '');
      expect(ing.amount, '');
    });

    test('toJson emits quantity, unit, and amount together', () {
      final ing = RecipeIngredient(name: '西红柿', quantity: '200', unit: 'g');
      final json = ing.toJson();
      expect(json['quantity'], '200');
      expect(json['unit'], 'g');
      expect(json['amount'], '200g');
    });

    test('amount is composed when constructor omits it', () {
      final a = RecipeIngredient(name: 'a', quantity: '200', unit: 'g');
      expect(a.amount, '200g');

      final b = RecipeIngredient(name: 'b', quantity: '', unit: '适量');
      expect(b.amount, '适量');

      final c = RecipeIngredient(name: 'c', quantity: '3', unit: '');
      expect(c.amount, '3');

      final d = RecipeIngredient(name: 'd', quantity: '', unit: '');
      expect(d.amount, '');
    });

    test('explicit amount overrides composed value (legacy round-trip)', () {
      final ing = RecipeIngredient(
        name: 'x',
        quantity: '200',
        unit: 'g',
        amount: 'legacy override',
      );
      expect(ing.amount, 'legacy override');
    });

    test('round-trip fromJson(toJson(...)) preserves all fields', () {
      final original = RecipeIngredient(
        name: '西红柿',
        quantity: '200',
        unit: 'g',
      );
      final restored = RecipeIngredient.fromJson(original.toJson());
      expect(restored.name, original.name);
      expect(restored.quantity, original.quantity);
      expect(restored.unit, original.unit);
      expect(restored.amount, original.amount);
    });

    test('copyWith preserves explicit amount when neither quantity nor unit changes',
        () {
      final original = RecipeIngredient(
        name: 'x',
        quantity: '200',
        unit: 'g',
        amount: '约 200g',
      );
      final updated = original.copyWith(name: 'y');
      expect(updated.amount, '约 200g');
    });

    test(
        'copyWith recomposes amount when quantity or unit changes and no explicit amount given',
        () {
      final original = RecipeIngredient(
        name: 'x',
        quantity: '200',
        unit: 'g',
        amount: '约 200g',
      );
      final updated = original.copyWith(quantity: '300');
      expect(updated.amount, '300g');
    });

    test('copyWith honors explicit amount even when changing quantity', () {
      final original = RecipeIngredient(
        name: 'x',
        quantity: '200',
        unit: 'g',
      );
      final updated = original.copyWith(quantity: '300', amount: '约 300g');
      expect(updated.amount, '约 300g');
    });
  });
}
