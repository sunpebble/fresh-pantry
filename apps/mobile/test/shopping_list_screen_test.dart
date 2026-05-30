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

import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('category headers collapse and expand their shopping items', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            shopping: const [
              ShoppingItem(
                id: 'tomato',
                name: '番茄',
                detail: '',
                category: FoodCategories.freshProduce,
              ),
              ShoppingItem(
                id: 'milk',
                name: '牛奶',
                detail: '',
                category: FoodCategories.dairyAndEggs,
              ),
            ],
          ),
        ],
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
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            shopping: const [
              ShoppingItem(
                id: 'tomato',
                name: '番茄',
                detail: '',
                category: FoodCategories.freshProduce,
              ),
            ],
          ),
        ],
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

  testWidgets('top add button focuses the quick add field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, shopping: const []),
        ],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final fieldBefore = tester.widget<EditableText>(find.byType(EditableText));
    expect(fieldBefore.focusNode.hasFocus, isFalse);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    final fieldAfter = tester.widget<EditableText>(find.byType(EditableText));
    expect(fieldAfter.focusNode.hasFocus, isTrue);
  });
}
