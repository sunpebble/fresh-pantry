import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/inventory_screen.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('inventory shows 补货 N 项 CTA when low-stock items exist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    // add_history now lives in Drift; preload the frequency record on the repo
    // and inject that repo so the low-stock CTA derives from it.
    final inventoryRepo = InventoryRepo(db)..hydrate(const []);
    await inventoryRepo.saveHistory({
      '米': {
        'count': 5,
        'category': FoodCategories.other,
        'storage': 'pantry',
        'unit': 'kg',
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          inventoryRepoProvider.overrideWithValue(inventoryRepo),
          shoppingSeedProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory_low_stock_cta')), findsOneWidget);
    expect(find.textContaining('补货 1 项'), findsOneWidget);
  });
}
