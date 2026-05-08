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
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'inventory screen does not show middle search or quick add inputs',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          _ingredient(
            name: '番茄',
            category: FoodCategories.freshProduce,
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

      // Positive structural assertions: the screen renders the inventory
      // chrome we expect.
      expect(find.byType(CategoryChips), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('食材库存'), findsOneWidget);
      // "不新鲜" leading filter chip is present and rendered before the
      // scrollable "全部" chip.
      expect(find.text('不新鲜'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('不新鲜')).dx,
        lessThan(tester.getTopLeft(find.text('全部')).dx),
      );
      // Inventory rows render with their stable swipe keys.
      expect(find.byKey(const ValueKey('inv_swipe_番茄_0')), findsOneWidget);

      // Negative assertions: middle search/quick add inputs and the
      // textContaining hints stay absent.
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('快速添加'), findsNothing);
      expect(find.textContaining('搜索'), findsNothing);
      expect(
        find.ancestor(of: find.text('不新鲜'), matching: find.byType(ListView)),
        findsNothing,
      );
    },
  );

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

      await tester.tap(find.text(FoodCategories.freshProduce));
      await tester.pumpAndSettle();

      await tester.tap(find.text('番茄'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(container.read(inventoryProvider).map((item) => item.name), [
        '米饭',
      ]);
    },
  );

  testWidgets('swipe delete removes the selected duplicate-name item', (
    tester,
  ) async {
    final firstItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    ).copyWith(quantity: '1');
    final secondItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    ).copyWith(quantity: '2');
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([firstItem.toJson(), secondItem.toJson()]),
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

    await tester.drag(
      find.byKey(const ValueKey('inv_swipe_番茄_1')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory_swipe_delete_番茄_1')));
    await tester.pumpAndSettle();

    final items = container.read(inventoryProvider);
    expect(items, hasLength(1));
    expect(items.single.quantity, '1');
  });

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

    expect(find.text('食材详情'), findsOneWidget);
    expect(find.text('多汁的果蔬生鲜食材'), findsOneWidget);
    expect(find.text('来源：本地食材知识库'), findsOneWidget);
    expect(find.text('建议存放：冰箱'), findsOneWidget);
    expect(find.text('保质期建议：7天'), findsOneWidget);
  });

  testWidgets(
    'ingredient detail action labels stay on one line on large phones',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final targetItem = _ingredient(
        name: '牛奶',
        category: FoodCategories.dairyAndEggs,
      ).copyWith(quantity: '240', unit: 'ml');
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
                  displayName: '牛奶',
                  description: '240 ml',
                  imageUrl: '',
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
            home: IngredientDetailScreen(ingredient: targetItem),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.text('编辑')).height, lessThanOrEqualTo(24));
      expect(tester.getSize(find.text('删除')).height, lessThanOrEqualTo(24));
    },
  );

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

      expect(find.text('加入购物清单'), findsOneWidget);
      expect(find.text('编辑'), findsNothing);
      expect(find.text('删除'), findsNothing);
    },
  );

  testWidgets('swiping an inventory item reveals delete without removing it', (
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

    await tester.drag(find.text('番茄'), const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).single.name, '番茄');
    expect(find.text('删除食材'), findsNothing);
    expect(
      find.byKey(const ValueKey('inventory_swipe_delete_番茄_0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('inventory_swipe_delete_番茄_0')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), isEmpty);
    expect(find.text('「番茄」已删除'), findsOneWidget);
  });

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
    await tester.tap(find.text('删除'));
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
    await tester.tap(find.text('删除'));
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

    await tester.tap(find.text('再买一次'));
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
    await tester.tap(find.text('编辑'));
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
