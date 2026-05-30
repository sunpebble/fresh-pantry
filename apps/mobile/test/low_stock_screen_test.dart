import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/low_stock_screen.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Map<String, dynamic> _entry(int count) => {
  'count': count,
  'category': FoodCategories.other,
  'storage': 'fridge',
  'unit': '个',
};

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  // add_history now lives in Drift; preload the frequency records on the repo
  // and inject it so the low-stock list derives from them.
  final inventoryRepo = InventoryRepo(db)..hydrate(const []);
  await inventoryRepo.saveHistory({'鸡蛋': _entry(5), '牛奶': _entry(4)});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        inventoryRepoProvider.overrideWithValue(inventoryRepo),
      ],
      child: const MaterialApp(home: LowStockScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists frequent items with all selected by default', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);
    // 两项默认全选 → CTA 计数为 2。
    expect(find.text('一键加入购物清单 (2)'), findsOneWidget);
  });

  testWidgets('toggling a row updates the selected count', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('鸡蛋'));
    await tester.pumpAndSettle();

    expect(find.text('一键加入购物清单 (1)'), findsOneWidget);
  });
}
