import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('search inventory result resets selected inventory category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          '牛奶',
        ).copyWith(category: FoodCategories.dairyAndEggs).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            const _FakeFoodDetailsClient(null),
          ),
          selectedCategoryProvider.overrideWith(
            (ref) => inventoryFilterNotFresh,
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '牛奶').first);
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 1);
    expect(container.read(selectedCategoryProvider), inventoryFilterAll);
    expect(find.text('牛奶'), findsOneWidget);
  });

  testWidgets('top search shows online food details when local lists miss', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '有机全脂牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl:
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/'
          'x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('食材百科'), findsOneWidget);
    expect(find.text('有机全脂牛奶'), findsOneWidget);
    expect(find.textContaining('Open Food Facts 返回的牛奶详情'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('有机全脂牛奶'));
    await tester.pumpAndSettle();

    expect(find.text('食材详情'), findsOneWidget);
    expect(find.text('分类：${FoodCategories.dairyAndEggs}'), findsOneWidget);
    expect(find.text('来源：Open Food Facts'), findsOneWidget);
  });

  testWidgets('top search summarizes generic online food details usefully', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '牛奶',
      description: 'Open Food Facts 记录的乳品蛋类食品。',
      imageUrl: null,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('食材百科'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '牛奶'), findsOneWidget);
    expect(find.text('乳品蛋类 · 冰箱保存 · 约 7 天'), findsOneWidget);
    expect(find.textContaining('Open Food Facts 记录'), findsNothing);
    expect(find.textContaining('Open Food Facts'), findsNothing);
  });

  testWidgets('top search shows online food details alongside local matches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          '牛奶',
        ).copyWith(category: FoodCategories.dairyAndEggs).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '有机全脂牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl: null,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('库存食材'), findsOneWidget);
    expect(find.text('食材百科'), findsOneWidget);
    expect(find.text('有机全脂牛奶'), findsOneWidget);
  });

  testWidgets('search shopping result expands the matched category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
      ]),
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 3),
          foodDetailsClientProvider.overrideWithValue(
            const _FakeFoodDetailsClient(null),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();
    expect(find.text('番茄'), findsNothing);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '番茄');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '番茄').first);
    await tester.pumpAndSettle();

    expect(find.text('番茄'), findsOneWidget);
  });
}

class _FakeFoodDetailsClient implements FoodDetailsClient {
  const _FakeFoodDetailsClient(this.details);

  final FoodDetails? details;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) async => details;
}

Ingredient _ingredient(
  String name, {
  FreshnessState state = FreshnessState.fresh,
}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: state,
    category: '测试',
    storage: IconType.fridge,
    expiryLabel: state == FreshnessState.fresh ? '新鲜' : '即将过期',
  );
}
