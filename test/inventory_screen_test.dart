import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ingredient_detail_screen.dart';
import 'package:fresh_pantry/screens/inventory_screen.dart';
import 'package:fresh_pantry/widgets/common/category_chips.dart';
import 'package:fresh_pantry/widgets/inventory/ingredient_card.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('inventory FK chrome: top bar + search + chips + 2-col grid', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          name: '番茄',
          category: FoodCategories.freshProduce,
        ).toJson(),
        _ingredient(
          name: '牛奶',
          category: FoodCategories.dairyAndEggs,
        ).copyWith(state: FreshnessState.expiringSoon).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // FkTopBar header + 共 N 件 subtitle.
    expect(find.text('我的食材'), findsOneWidget);
    expect(find.text('共 2 件'), findsOneWidget);

    // Search field is present (FK redesign adds it inline).
    final searchHint = find.text('搜索食材');
    expect(searchHint, findsOneWidget);

    // Filter chips: "全部 · 2" + the 不新鲜 status chip with its count.
    expect(find.text('全部 · 2'), findsOneWidget);
    expect(find.text('不新鲜 · 1'), findsOneWidget);

    // Search by name narrows the visible cards.
    await tester.enterText(find.widgetWithText(TextField, '搜索食材'), '番茄');
    await tester.pumpAndSettle();
    // 番茄 is now visible both in the search field text and the card name.
    expect(find.widgetWithText(IngredientCard, '番茄'), findsOneWidget);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsNothing);
  });

  testWidgets(
    'deletes the selected filtered inventory item by original index',
    (tester) async {
      final otherCategoryItem = _ingredient(
        name: '米饭',
        category: FoodCategories.other,
      );
      final targetCategoryItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      );
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          otherCategoryItem.toJson(),
          targetCategoryItem.toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: Scaffold(body: InventoryScreen()));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FK chip text now shows "果蔬生鲜 · 1" — match by prefix.
      await tester.tap(find.textContaining(FoodCategories.freshProduce));
      await tester.pumpAndSettle();

      await tester.tap(find.text('番茄'));
      await tester.pumpAndSettle();
      // FK redesign: delete is an icon button on the hero, dialog still has "删除" text.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(container.read(inventoryProvider).map((item) => item.name), [
        '米饭',
      ]);
    },
  );

  testWidgets(
    'detail delete removes the correct duplicate-name inventory item',
    (tester) async {
      final firstItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      ).copyWith(quantity: '1');
      final secondItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      ).copyWith(quantity: '2');
      SharedPreferences.setMockInitialValues({
        'inventory_items':
            jsonEncode([firstItem.toJson(), secondItem.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                home: Scaffold(body: InventoryScreen()),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FK redesign: each card is keyed by inv_<name>_<index>. Tap the
      // second duplicate to open detail.
      await tester.tap(find.byKey(const ValueKey('inv_番茄_1')));
      await tester.pumpAndSettle();

      // Delete via the hero icon button + confirm dialog.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      final items = container.read(inventoryProvider);
      expect(items, hasLength(1));
      expect(items.single.quantity, '1');
    },
  );

  testWidgets('tapping an inventory card opens food details', (tester) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(
              FoodDetails(
                displayName: '番茄',
                description: '多汁的果蔬生鲜食材',
                imageUrl: '',
                category: FoodCategories.freshProduce,
                storage: IconType.fridge,
                shelfLifeDays: 7,
                source: '本地食材知识库',
                fetchedAt: DateTime.utc(2026, 5, 1),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();

    // FK redesign: AppBar gone; hero shows display name + description card +
    // info-list rows ("分类|存放位置|保质期建议|来源" → "value").
    expect(find.text('多汁的果蔬生鲜食材'), findsOneWidget);
    expect(find.text('保质期建议'), findsOneWidget);
    expect(find.text('7天'), findsOneWidget);
    expect(find.text('本地食材知识库'), findsOneWidget);
    // Name appears in the hero — at least one instance must exist on screen.
    expect(find.text('番茄'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'ingredient detail hides inventory-only actions for online result',
    (tester) async {
      final onlineItem = _ingredient(
        name: '牛奶',
        category: FoodCategories.dairyAndEggs,
      );
      SharedPreferences.setMockInitialValues({'inventory_items': '[]'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            foodDetailsClientProvider.overrideWithValue(
              _FakeFoodDetailsClient(
                FoodDetails(
                  displayName: '牛奶',
                  description: '乳品蛋类食材',
                  imageUrl: null,
                  category: FoodCategories.dairyAndEggs,
                  storage: IconType.fridge,
                  shelfLifeDays: 7,
                  source: 'Open Food Facts',
                  fetchedAt: DateTime.utc(2026, 5, 1),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: IngredientDetailScreen(ingredient: onlineItem),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FK redesign: action button reads "加入清单"; edit/delete are icon-only
      // and only render when the item is in inventory (this one is not).
      expect(find.text('加入清单'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    },
  );

  testWidgets('delete snackbar with undo auto dismisses after timeout', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    // FK redesign: delete icon button on hero + dialog "删除" confirmation.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsNothing);
  });

  testWidgets('delete undo restores the original inventory position', (
    tester,
  ) async {
    final firstItem = _ingredient(
      name: '牛奶',
      category: FoodCategories.dairyAndEggs,
    );
    final secondItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    final thirdItem = _ingredient(name: '米饭', category: FoodCategories.other);
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        firstItem.toJson(),
        secondItem.toJson(),
        thirdItem.toJson(),
      ]),
      'add_history': jsonEncode({
        '番茄': {
          'count': 1,
          'category': FoodCategories.freshProduce,
          'storage': 'fridge',
          'unit': '份',
        },
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    // FK redesign: delete icon button on hero + dialog "删除" confirmation.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).map((item) => item.name), [
      '牛奶',
      '番茄',
      '米饭',
    ]);
    final history = jsonDecode(prefs.getString('add_history')!);
    expect(history['番茄']['count'], 1);
  });

  testWidgets('buy again reports duplicate shopping items', (tester) async {
    final targetItem = _ingredient(
      name: '牛奶',
      category: FoodCategories.dairyAndEggs,
    ).copyWith(state: FreshnessState.expiringSoon, expiryLabel: '明天过期');
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'milk',
          name: '牛奶',
          detail: '',
          category: FoodCategories.dairyAndEggs,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // FK redesign relabels the inline buy-again CTA to "加购".
    await tester.tap(find.text('加购'));
    await tester.pumpAndSettle();

    expect(find.text('「牛奶」已在购物清单中'), findsOneWidget);
  });

  testWidgets('edit action opens form and updates selected inventory item', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    // FK redesign: edit is an icon button on the hero.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('编辑食材'), findsOneWidget);
    expect(find.widgetWithText(TextField, '番茄'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '番茄'), '樱桃番茄');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).single.name, '樱桃番茄');
    expect(find.text('「樱桃番茄」已更新'), findsOneWidget);
  });
}

Ingredient _ingredient({required String name, required String category}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: category,
    storage: IconType.fridge,
    expiryLabel: '新鲜',
  );
}

class _FakeFoodDetailsClient implements FoodDetailsClient {
  _FakeFoodDetailsClient(this.details);

  final FoodDetails details;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) async => details;
}
