import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/widgets/dashboard/low_stock_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _entry(int count) => {
      'count': count,
      'category': FoodCategories.other,
      'storage': 'fridge',
      'unit': '个',
    };

Future<Widget> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> history,
  required List<Ingredient> inventory,
}) async {
  SharedPreferences.setMockInitialValues({'add_history': jsonEncode(history)});
  final prefs = await SharedPreferences.getInstance();
  final w = ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(inventory),
      shoppingSeedProvider.overrideWithValue(const []),
    ],
    child: const MaterialApp(home: Scaffold(body: LowStockCard())),
  );
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
  return w;
}

void main() {
  testWidgets('renders empty (SizedBox.shrink) when no low-stock items',
      (tester) async {
    await _pump(tester, history: {}, inventory: []);
    expect(find.byKey(const Key('low_stock_bulk_add_cta')), findsNothing);
  });

  testWidgets('renders rows + CTA with count when items present',
      (tester) async {
    await _pump(
      tester,
      history: {'米': _entry(5), '鸡蛋': _entry(3)},
      inventory: [],
    );
    expect(find.text('库存不足 (2 项)'), findsOneWidget);
    expect(find.text('米'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.byKey(const Key('low_stock_bulk_add_cta')), findsOneWidget);
    expect(find.textContaining('全部加入购物清单 (2)'), findsOneWidget);
  });

  testWidgets('tap CTA → confirm → items added to shopping list',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'add_history': jsonEncode({'米': _entry(5)})});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          inventorySeedProvider.overrideWithValue(const []),
          shoppingSeedProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: Scaffold(body: LowStockCard())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('low_stock_bulk_add_cta')));
    await tester.pumpAndSettle();
    expect(find.text('确认加入'), findsOneWidget);
    await tester.tap(find.text('确认加入'));
    await tester.pumpAndSettle();

    // Verify shopping provider received the add.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    expect(container.read(shoppingProvider).length, 1);
    expect(container.read(shoppingProvider).first.name, '米');
  });
}
