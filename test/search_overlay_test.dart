import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/search_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/widgets/common/search_overlay.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows history and reuses selected term', (tester) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(searchHistoryProvider.notifier).add('苹');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: SearchOverlay()),
        ),
      ),
    );

    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.text('苹'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, '苹'));
    await tester.pump();

    expect(container.read(searchProvider), '苹');
  });

  testWidgets('builds inventory and shopping results lazily', (tester) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('苹果', category: FoodCategories.freshProduce).toJson(),
      ]),
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'apple-juice',
          name: '苹果汁',
          detail: '1 瓶',
          category: FoodCategories.other,
        ).toJson(),
      ]),
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: SearchOverlay()),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '苹');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('库存食材'), findsOneWidget);
    expect(find.text('购物清单'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '苹果'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '苹果汁'), findsOneWidget);
  });
}

Ingredient _ingredient(String name, {String? category}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '个',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: category,
    storage: IconType.fridge,
  );
}
