import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/howtocook_parser.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/howtocook/$name').readAsStringSync();

  group('parseHowToCookMarkdown', () {
    test('解析「可乐鸡翅」（* bullet、计算段含分量）', () {
      final recipe = parseHowToCookMarkdown(
        fixture('可乐鸡翅.md'),
        relativePath: 'meat_dish/可乐鸡翅.md',
      );

      expect(recipe, isNotNull);
      expect(recipe!.id, 'howtocook:meat_dish/可乐鸡翅');
      expect(recipe.name, '可乐鸡翅');
      expect(recipe.category, '荤菜');
      expect(recipe.difficulty, 3);
      expect(recipe.cookingMinutes, 40);
      expect(recipe.description, contains('可乐鸡翅'));
      expect(recipe.ingredients.map((i) => i.name), contains('鸡翅中'));
      expect(recipe.ingredients.map((i) => i.name), contains('可乐'));
      expect(recipe.ingredients.length, 8);
      expect(recipe.ingredients.every((i) => i.amount.isEmpty), isTrue);
      expect(recipe.steps.length, 7);
      expect(recipe.steps.first, contains('鸡翅入锅'));
    });

    test('解析「冷吃兔」（- bullet、计算段是公式）', () {
      final recipe = parseHowToCookMarkdown(
        fixture('冷吃兔.md'),
        relativePath: 'meat_dish/冷吃兔.md',
      );

      expect(recipe, isNotNull);
      expect(recipe!.name, '冷吃兔');
      expect(recipe.difficulty, 4);
      expect(recipe.cookingMinutes, 60);
      expect(recipe.ingredients.map((i) => i.name), contains('兔肉'));
      expect(recipe.ingredients.length, 17);
      expect(recipe.steps.length, 10);
    });

    test('无 # 标题 → null', () {
      expect(
        parseHowToCookMarkdown(
          '没有标题\n\n## 操作\n\n1. 做菜',
          relativePath: 'meat_dish/x.md',
        ),
        isNull,
      );
    });

    test('无「## 操作」段 → null（非菜谱，如 README）', () {
      expect(
        parseHowToCookMarkdown(
          '# 介绍\n\n一些说明文字',
          relativePath: 'meat_dish/README.md',
        ),
        isNull,
      );
    });

    test('未知目录 → 类别「其他」', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试菜的做法\n\n## 必备原料和工具\n\n- 盐\n\n## 操作\n\n1. 做',
        relativePath: 'unknown_dir/测试菜.md',
      );
      expect(recipe!.category, '其他');
    });

    test('无难度行 → difficulty 0、cookingMinutes 兜底 30', () {
      final recipe = parseHowToCookMarkdown(
        '# 测试菜的做法\n\n## 必备原料和工具\n\n- 盐\n\n## 操作\n\n1. 做',
        relativePath: 'vegetable_dish/测试菜.md',
      );
      expect(recipe!.difficulty, 0);
      expect(recipe.cookingMinutes, 30);
    });
  });
}
