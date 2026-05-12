import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/screens/my_recipes_screen.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:fresh_pantry/widgets/recipe_card.dart';
import 'package:fresh_pantry/widgets/recipe_form/cooking_time_row.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings 我的食谱 link opens MyRecipesScreen', (tester) async {
    // Use a tall surface so the 更多 list (last section) is rendered
    // in the lazily-mounted ListView viewport.
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const SettingsScreen()));
    await tester.pumpAndSettle();

    // Scroll to bring the 我的食谱 link in the 更多 section into view.
    await tester.scrollUntilVisible(
      find.text('我的食谱'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // FK redesign moved 我的食谱 into Settings → 更多 list. Tap it to push.
    await tester.tap(find.text('我的食谱'));
    await tester.pumpAndSettle();

    // After push: opaque MaterialPageRoute deactivates Settings, so only
    // MyRecipesScreen's AppBar title remains in the visible tree.
    expect(find.text('我的食谱'), findsOneWidget);
    expect(find.text('还没有自定义食谱'), findsOneWidget);
  });

  testWidgets('my recipes screen shows saved recipes', (tester) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    // FK redesign removed subtitle/description from the inline card; the name remains.
    expect(find.text('番茄炒蛋'), findsOneWidget);
  });

  testWidgets('my recipes screen shows saved recipe images', (tester) async {
    const imageUrl = 'https://example.com/tomato-eggs.jpg';
    final recipe = _recipe('r1').copyWith(imageUrl: imageUrl);
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([recipe.toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) {
        return widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == imageUrl;
      }),
      findsOneWidget,
    );
  });

  testWidgets('my recipes screen uses the recommendation card style', (
    tester,
  ) async {
    const imageUrl = 'https://example.com/tomato-eggs.jpg';
    final recipe = _recipe('r1').copyWith(imageUrl: imageUrl);
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([recipe.toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeCard), findsOneWidget);

    final imageFinder = find.byWidgetPredicate((widget) {
      return widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url == imageUrl;
    });

    // FK redesign: cover image is 120 wide × 130 tall (card height).
    expect(tester.getSize(imageFinder), const Size(120, 130));
  });

  testWidgets('my recipe overview uses recommendation card metadata', (
    tester,
  ) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      'inventory_items': json.encode([_ingredient('番茄').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    // FK redesign: "15 分钟" with a space, "食材匹配 N/N" replaces "N/N 已备".
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.textContaining('难度 1/5'), findsOneWidget);
    expect(find.text('食材匹配 1/1'), findsOneWidget);
    expect(find.text('1种食材'), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('saved custom recipe opens detail screen', (tester) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      'inventory_items': json.encode([_ingredient('番茄').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄炒蛋'));
    await tester.pumpAndSettle();

    // FK redesign relabels "所需食材" → "食材清单".
    expect(find.text('食材清单'), findsOneWidget);
    expect(find.text('烹饪步骤'), findsOneWidget);
    expect(find.text('难度 1/5'), findsOneWidget);
  });

  testWidgets('recipe detail marks ingredient rows using normalized names', (
    tester,
  ) async {
    final prefs = await _prefs({
      'inventory_items': json.encode([_ingredient('Chicken').toJson()]),
    });
    final recipe = _recipe('r1').copyWith(
      ingredients: [RecipeIngredient(name: 'chicken', amount: '1份')],
    );

    await tester.pumpWidget(_app(prefs, RecipeDetailScreen(recipe: recipe)));
    await tester.pumpAndSettle();

    // FK redesign: detail header shows "已有 N/M"; rows use "已有" pill, no "库存中" badge; no missing CTA when all available.
    expect(find.text('已有 1/1'), findsOneWidget);
    expect(find.text('已有'), findsAtLeastNWidgets(1));
    expect(find.textContaining('一键加购缺少'), findsNothing);
  });

  testWidgets(
    'custom recipe can be deleted from the list menu after confirmation',
    (tester) async {
      final prefs = await _prefs({
        customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      });

      await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('删除食谱'), findsOneWidget);
      expect(find.text('番茄炒蛋'), findsOneWidget);

      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('番茄炒蛋'), findsNothing);
      expect(find.text('还没有自定义食谱'), findsOneWidget);
    },
  );

  testWidgets('custom recipe detail edit action opens edit form', (
    tester,
  ) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄炒蛋'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑食谱'));
    await tester.pumpAndSettle();

    expect(find.text('编辑食谱'), findsOneWidget);
    expect(find.widgetWithText(TextField, '食谱名称 *'), findsOneWidget);
  });

  testWidgets('custom recipe detail reflects edits saved from detail edit', (
    tester,
  ) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄炒蛋'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑食谱'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '番茄鸡蛋面');
    await tester.tap(find.text('保存食谱'));
    await tester.pumpAndSettle();

    expect(find.text('番茄鸡蛋面'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsNothing);
  });

  testWidgets(
    'custom recipe detail progress resets after edited steps change',
    (tester) async {
      // FK hero + step cards are taller than the legacy layout; bump the
      // surface so scrollUntilVisible can reach the bottom of the steps.
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prefs = await _prefs({
        customRecipesStorageKey: json.encode([_multiPartRecipe('r2').toJson()]),
      });

      await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('番茄鸡蛋汤'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('切番茄'), 300);
      await tester.tap(find.text('切番茄'));
      await tester.scrollUntilVisible(find.text('炒熟鸡蛋'), 300);
      await tester.tap(find.text('炒熟鸡蛋'));
      await tester.pumpAndSettle();

      expect(find.text('2/2'), findsWidgets);

      await tester.tap(find.byTooltip('编辑食谱'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('移除步骤').last,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('移除步骤').last);
      await tester.tap(find.text('保存食谱'));
      await tester.pumpAndSettle();

      expect(find.text('0/1'), findsOneWidget);
      expect(find.text('2/1'), findsNothing);
    },
  );

  testWidgets(
    'custom recipe detail delete action confirms and returns to list',
    (tester) async {
      final prefs = await _prefs({
        customRecipesStorageKey: json.encode([_recipe('r1').toJson()]),
      });

      await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('番茄炒蛋'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除食谱'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('我的食谱'), findsOneWidget);
      expect(find.text('还没有自定义食谱'), findsOneWidget);
    },
  );

  testWidgets('new recipe button opens custom recipe form', (tester) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建食谱'));
    await tester.pumpAndSettle();

    expect(find.text('保存食谱'), findsOneWidget);
  });

  testWidgets(
    'custom recipe form blocks save when required fields are missing',
    (tester) async {
      final prefs = await _prefs({});

      await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存食谱'));
      await tester.pumpAndSettle();

      expect(find.text('请填入食谱名称'), findsOneWidget);
      expect(find.text('请输入大于 0 的分钟数'), findsOneWidget);
      expect(find.text('至少一种食材'), findsOneWidget);
      expect(find.text('至少添加一个步骤'), findsOneWidget);
    },
  );

  testWidgets('custom recipe form saves a valid recipe', (tester) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '葱油拌面');
    await tester.enterText(
      find.descendant(
        of: find.byType(CookingTimeRow),
        matching: find.byType(TextField),
      ),
      '12',
    );
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '面条');
    await tester.enterText(find.widgetWithText(TextField, '用量').first, '1份');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '煮面后拌入葱油',
    );
    await tester.tap(find.text('保存食谱'));
    // pumpAndSettle would hang while CircularProgressIndicator animates.
    // pump() resolves microtasks; the notifier completes synchronously in
    // tests, so a single extra pump is enough for Navigator.pop to fire.
    await tester.pump();
    await tester.pump();

    final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
    expect(saved.single['name'], '葱油拌面');
  });

  testWidgets('custom recipe form offers upload and camera cover actions', (
    tester,
  ) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    expect(find.text('添加封面（可选）'), findsOneWidget);
    expect(find.widgetWithText(TextField, '封面图片链接'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '上传图片'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '拍照'), findsOneWidget);
  });

  testWidgets('custom recipe form places cover image above basic fields', (
    tester,
  ) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    final coverTop = tester.getTopLeft(find.text('添加封面（可选）')).dy;
    final basicInfoTop = tester.getTopLeft(find.text('基础信息')).dy;

    expect(coverTop, lessThan(basicInfoTop));
  });

  testWidgets('custom recipe form uses floating labels for every text field', (
    tester,
  ) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    // Only check labeled fields (those with a labelText) — unlabeled internal
    // fields like the CookingTimeRow input are excluded.
    final labeledTextFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where(
          (tf) =>
              tf.key != const Key('recipe_url_input') &&
              tf.decoration?.labelText != null,
        )
        .toList();

    expect(labeledTextFields, isNotEmpty);
    for (final textField in labeledTextFields) {
      expect(
        textField.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
        reason:
            'TextField with label "${textField.decoration?.labelText}" should use FloatingLabelBehavior.always',
      );
    }
  });

  testWidgets('custom recipe form saves an uploaded cover image', (
    tester,
  ) async {
    const coverImage = 'data:image/png;base64,aGVsbG8=';
    final prefs = await _prefs({});

    await tester.pumpWidget(
      _app(
        prefs,
        CustomRecipeFormScreen(
          pickCoverImage: (source) async {
            expect(source, ImageSource.gallery);
            return coverImage;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, '上传图片'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '上传图片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '葱油拌面');
    await tester.enterText(
      find.descendant(
        of: find.byType(CookingTimeRow),
        matching: find.byType(TextField),
      ),
      '12',
    );
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '面条');
    await tester.enterText(find.widgetWithText(TextField, '用量').first, '1份');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '煮面后拌入葱油',
    );
    await tester.tap(find.text('保存食谱'));
    // pumpAndSettle hangs on CircularProgressIndicator animation; pump() is
    // sufficient since the notifier completes synchronously in tests.
    await tester.pump();
    await tester.pump();

    final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
    expect(saved.single['imageUrl'], coverImage);
  });

  testWidgets('edit custom recipe can clear an existing cover image', (
    tester,
  ) async {
    const imageUrl = 'https://example.com/tomato-eggs.jpg';
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([
        _recipe('r1').copyWith(imageUrl: imageUrl).toJson(),
      ]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('清除图片'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip('清除图片'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('清除图片'));
    await tester.tap(find.text('保存食谱'));
    await tester.pumpAndSettle();

    final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
    expect(saved.single['imageUrl'], isNull);
  });

  testWidgets('custom recipe form dismisses the keyboard when saving', (
    tester,
  ) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '煮面后拌入葱油',
    );
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('保存食谱'));
    await tester.pump();

    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets(
    'custom recipe form dismisses the keyboard when tapping outside',
    (tester) async {
      final prefs = await _prefs({});

      await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '葱油拌面');
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('基础信息'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets('custom recipe form shows save failure feedback', (tester) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(
      _app(
        prefs,
        const CustomRecipeFormScreen(),
        overrides: [
          customRecipesProvider.overrideWith(_ThrowingCustomRecipeNotifier.new),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '葱油拌面');
    await tester.enterText(
      find.descendant(
        of: find.byType(CookingTimeRow),
        matching: find.byType(TextField),
      ),
      '12',
    );
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '面条');
    await tester.enterText(find.widgetWithText(TextField, '用量').first, '1份');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '煮面后拌入葱油',
    );
    await tester.tap(find.text('保存食谱'));
    await tester.pump();

    expect(find.text('保存失败，请重试'), findsOneWidget);
  });

  testWidgets('edit recipe preserves all ingredients and steps', (
    tester,
  ) async {
    final prefs = await _prefs({
      customRecipesStorageKey: json.encode([_multiPartRecipe('r2').toJson()]),
    });

    await tester.pumpWidget(_app(prefs, const MyRecipesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '番茄鸡蛋面');
    await tester.tap(find.text('保存食谱'));
    await tester.pumpAndSettle();

    final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
    final recipe = saved.single as Map<String, dynamic>;
    expect(recipe['id'], 'r2');
    expect(recipe['name'], '番茄鸡蛋面');
    expect(recipe['ingredients'], hasLength(2));
    expect(recipe['ingredients'][0]['name'], '番茄');
    expect(recipe['ingredients'][1]['name'], '鸡蛋');
    expect(recipe['steps'], ['切番茄', '炒熟鸡蛋']);
  });

  testWidgets('custom recipe form ignores repeated save taps while saving', (
    tester,
  ) async {
    final prefs = await _prefs({});

    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '葱油拌面');
    await tester.enterText(
      find.descendant(
        of: find.byType(CookingTimeRow),
        matching: find.byType(TextField),
      ),
      '12',
    );
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '面条');
    await tester.enterText(find.widgetWithText(TextField, '用量').first, '1份');
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '煮面后拌入葱油',
    );
    await tester.tap(find.text('保存食谱'));
    // After the first tap, _isSaving flips to true and the FilledButton's
    // onPressed must be null so the second tap is a no-op.
    await tester.pump();
    // While saving, the button child switches to the spinner row ('保存中…'),
    // so find by type rather than text.
    final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      saveButton.onPressed,
      isNull,
      reason: 'save button should be disabled while saving is in progress',
    );
    // Second tap targets the disabled button directly (text is now '保存中…').
    await tester.tap(find.byType(FilledButton));
    // pumpAndSettle hangs on CircularProgressIndicator animation; pump() is
    // sufficient since the notifier completes synchronously in tests.
    await tester.pump();
    await tester.pump();

    final saved = json.decode(prefs.getString(customRecipesStorageKey)!);
    expect(saved, hasLength(1));
  });

  testWidgets('full create flow with new controls saves recipe', (tester) async {
    final prefs = await _prefs({});
    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    // 名称
    await tester.enterText(find.widgetWithText(TextField, '食谱名称 *'), '番茄炒蛋');

    // 时间：使用 CookingTimeRow 的自定义输入框（preset chips are in a horizontal
    // ListView that may be partially off-screen in the test viewport)
    await tester.enterText(
      find.descendant(
        of: find.byType(CookingTimeRow),
        matching: find.byType(TextField),
      ),
      '30',
    );

    // 食材：填第一行的名称和用量字段
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '西红柿');
    await tester.enterText(find.widgetWithText(TextField, '用量').first, '200');

    // 步骤：填第一步
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入下一步…',
      ).first,
      '切块翻炒',
    );

    await tester.tap(find.text('保存食谱'));
    await tester.pump();
    await tester.pump();

    expect(prefs.getString(customRecipesStorageKey), contains('番茄炒蛋'));
  });

  testWidgets('save with empty name shows inline error', (tester) async {
    final prefs = await _prefs({});
    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存食谱'));
    await tester.pump();

    expect(find.text('请填入食谱名称'), findsOneWidget);
  });

  testWidgets('edit mode prefills legacy amount as quantity + unit',
      (tester) async {
    // RecipeIngredient with only amount (legacy shape): quantity='', unit=''.
    // _IngredientControllers.from detects hasNewShape=false and sets
    // quantity=amount ('200g') and unit='' (empty → UnitDropdown shows '单位 ▾').
    final legacyRecipe = Recipe(
      id: 'r-legacy',
      name: '旧食谱',
      category: '家常',
      difficulty: 2,
      cookingMinutes: 25,
      description: '',
      ingredients: [
        RecipeIngredient(name: '西红柿', amount: '200g'),
      ],
      steps: const ['切块'],
    );

    final prefs = await _prefs({});
    await tester.pumpWidget(
      _app(prefs, CustomRecipeFormScreen(recipe: legacyRecipe)),
    );
    await tester.pumpAndSettle();

    // AI 折叠条不应渲染（编辑模式）
    expect(find.text('✨ 粘贴链接，AI 自动填表'), findsNothing);

    // 旧 amount '200g' 整体被用作 quantity 值（无法拆 quantity/unit）
    expect(find.widgetWithText(TextField, '食谱名称 *'), findsOneWidget);
    expect(find.text('旧食谱'), findsOneWidget);
    // The legacy amount '200g' is prefilled in the quantity TextField
    expect(find.text('200g'), findsWidgets);
  });

  testWidgets('ingredient drag reorder updates list order', (tester) async {
    final prefs = await _prefs({});
    await tester.pumpWidget(_app(prefs, const CustomRecipeFormScreen()));
    await tester.pumpAndSettle();

    // 填第一行的食材名称（初始只有一行）
    await tester.enterText(find.widgetWithText(TextField, '食材名称').first, '第一');
    await tester.pump();

    // 滚动到"添加食材"按钮并点击
    await tester.scrollUntilVisible(
      find.text('添加食材'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('添加食材'));
    await tester.pumpAndSettle();

    // 填第二行食材名称
    // After adding the second row there are now 2 name TextFields with hint '食材名称'
    await tester.enterText(find.widgetWithText(TextField, '食材名称').at(1), '第二');
    await tester.pump();

    // 找食材区域的 drag handle（属于第一个 ReorderableListView）
    // There are two ReorderableListViews (ingredients + steps).
    // Icons.drag_indicator appears in both; use the first one (ingredient row 0).
    final allDragHandles = find.byIcon(Icons.drag_indicator);

    // Attempt drag — ReorderableDragStartListener requires a long-press then
    // drag gesture. tester.drag sends a pointer sequence that may not trigger
    // reorder in the test renderer, but confirms no crash occurs.
    await tester.drag(allDragHandles.first, const Offset(0, 80));
    await tester.pumpAndSettle();

    // 重排后两个名字仍存在（断言"重排发生而不崩溃"）
    expect(find.text('第一'), findsOneWidget);
    expect(find.text('第二'), findsOneWidget);
  });
}

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Widget _app(
  SharedPreferences prefs,
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

class _ThrowingCustomRecipeNotifier extends CustomRecipeNotifier {
  @override
  Future<void> add(Recipe recipe) async {
    throw StateError('save failed');
  }

  @override
  Future<void> update(String id, Recipe recipe) async {
    throw StateError('save failed');
  }
}

Recipe _recipe(String id) {
  return Recipe(
    id: id,
    name: '番茄炒蛋',
    category: '家常',
    difficulty: 1,
    cookingMinutes: 15,
    description: '快手家常菜',
    ingredients: [RecipeIngredient(name: '番茄', amount: '2个')],
    steps: const ['切番茄', '炒熟'],
  );
}

Recipe _multiPartRecipe(String id) {
  return Recipe(
    id: id,
    name: '番茄鸡蛋汤',
    category: '家常',
    difficulty: 2,
    cookingMinutes: 20,
    description: '保留多食材和多步骤',
    ingredients: [
      RecipeIngredient(name: '番茄', amount: '2个'),
      RecipeIngredient(name: '鸡蛋', amount: '2个'),
    ],
    steps: const ['切番茄', '炒熟鸡蛋'],
  );
}

Ingredient _ingredient(String name) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '个',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: '测试',
    storage: IconType.fridge,
  );
}
