import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/data/food_knowledge.dart';

void main() {
  group('FoodCategories', () {
    test('exposes the fixed app categories in display order', () {
      expect(FoodCategories.values, const [
        '乳品蛋类',
        '果蔬生鲜',
        '肉类海鲜',
        '香料草本',
        '其他',
      ]);
    });

    test('normalizes legacy and custom categories into the fixed set', () {
      expect(FoodCategories.normalize('乳制品与蛋类'), FoodCategories.dairyAndEggs);
      expect(FoodCategories.normalize('新鲜蔬果'), FoodCategories.freshProduce);
      expect(FoodCategories.normalize('蔬菜'), FoodCategories.freshProduce);
      expect(FoodCategories.normalize('肉类与海鲜'), FoodCategories.meatAndSeafood);
      expect(FoodCategories.normalize('香料与草本'), FoodCategories.herbsAndSpices);
      expect(FoodCategories.normalize('自定义分类'), FoodCategories.other);
      expect(FoodCategories.normalize('  '), isNull);
    });
  });

  group('FoodKnowledge.lookup', () {
    test('returns defaults for exact keyword match', () {
      final result = FoodKnowledge.lookup('牛奶');
      expect(result, isNotNull);
      expect(result!.shelfLifeDays, greaterThan(0));
    });

    test('matches when name contains keyword (substring)', () {
      final result = FoodKnowledge.lookup('新鲜牛奶两盒');
      expect(result, isNotNull);
    });

    test('returns null for unknown food name', () {
      expect(FoodKnowledge.lookup('未知食品XYZ123'), isNull);
    });

    test('returns null for empty string', () {
      expect(FoodKnowledge.lookup(''), isNull);
    });

    test('returns null for whitespace-only string', () {
      expect(FoodKnowledge.lookup('   '), isNull);
    });
  });

  group('FoodKnowledge.englishName', () {
    test('returns null for unknown name', () {
      expect(FoodKnowledge.englishName('未知食品XYZ'), isNull);
    });

    test('returns null for empty string', () {
      expect(FoodKnowledge.englishName(''), isNull);
    });

    test('returns non-null for known entry', () {
      // At least one Chinese food should have an English name mapping
      final known = ['大米', '牛肉', '猪肉', '鸡肉', '鱼'];
      final found = known.any((n) => FoodKnowledge.englishName(n) != null);
      expect(found, isTrue, reason: 'at least one common food should have English name');
    });
  });

  group('FoodKnowledge.categoryFor', () {
    test('returns the stable category for known ingredients', () {
      expect(FoodKnowledge.categoryFor('鸡蛋'), FoodCategories.dairyAndEggs);
      expect(FoodKnowledge.categoryFor('大米'), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('黑胡椒'), FoodCategories.herbsAndSpices);
    });

    test('uses the longest keyword match before broader matches', () {
      expect(FoodKnowledge.categoryFor('番茄酱'), FoodCategories.other);
    });

    test('falls back for blank and unknown names', () {
      expect(FoodKnowledge.categoryFor(''), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('  '), FoodCategories.other);
      expect(FoodKnowledge.categoryFor('未知食材'), FoodCategories.other);
    });

    test('normalizes fallback categories into the fixed set', () {
      expect(
        FoodKnowledge.categoryFor('未知食材', fallback: '自定义分类'),
        FoodCategories.other,
      );
      expect(
        FoodKnowledge.categoryFor('未知食材', fallback: '蔬菜'),
        FoodCategories.freshProduce,
      );
    });
  });
}
