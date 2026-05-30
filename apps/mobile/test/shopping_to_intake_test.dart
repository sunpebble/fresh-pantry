import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/shopping_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

void main() {
  testWidgets('sticky CTA appears when any item is checked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final seed = [
      ShoppingItem(
        id: 'si1',
        name: '苹果',
        detail: '5 个',
        category: FoodCategories.other,
        isChecked: true,
      ),
      ShoppingItem(
        id: 'si2',
        name: '盐',
        detail: '1 袋',
        category: FoodCategories.other,
        isChecked: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, shopping: seed),
        ],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shopping_to_intake_cta')), findsOneWidget);
    expect(find.textContaining('1 项'), findsOneWidget);
  });
}
