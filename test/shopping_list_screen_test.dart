import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/shopping_list_screen.dart';
import 'package:fresh_pantry/widgets/shared/cat_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('category headers collapse and expand their shopping items', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
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
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(FoodCategories.freshProduce), findsOneWidget);
    // FK CatIcon replaces the old Material outlined icon.
    expect(find.byType(CatIcon), findsAtLeastNWidgets(1));
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();

    expect(find.text(FoodCategories.freshProduce), findsOneWidget);
    expect(find.text('番茄'), findsNothing);
    expect(find.text('牛奶'), findsOneWidget);

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();

    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('inline X icon on a shopping row deletes it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
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
            return const MaterialApp(
              home: Scaffold(body: ShoppingListScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider).single.name, '番茄');

    // FK redesign: each row has an inline X icon for delete.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider), isEmpty);
    expect(find.text('「番茄」已删除'), findsOneWidget);
  });

  testWidgets('smart planner view recipe opens the suggested recipe detail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'pasta',
          name: '意大利面',
          detail: '200g',
          category: FoodCategories.other,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('查看食谱'), findsOneWidget);

    await tester.tap(find.text('查看食谱'));
    await tester.pumpAndSettle();

    expect(find.text('经典卡博纳拉意面'), findsOneWidget);
    // FK redesign relabels "所需食材" → "食材清单".
    expect(find.text('食材清单'), findsOneWidget);
  });
}
