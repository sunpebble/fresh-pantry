import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('add ingredient screen no longer shows barcode scanner entry', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扫描条码'), findsNothing);
    expect(find.text('快速识别商品信息'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.text('食材名称'), findsOneWidget);
  });

  testWidgets('add ingredient name field does not inherit focused outline', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AddIngredientScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '例如：牛奶、鸡蛋、番茄...',
    );

    expect(nameField, findsOneWidget);
    await tester.tap(nameField);
    await tester.pump();

    final decoration = tester.widget<TextField>(nameField).decoration;
    expect(decoration?.focusedBorder, same(InputBorder.none));
    expect(decoration?.enabledBorder, same(InputBorder.none));
    expect(decoration?.border, same(InputBorder.none));

    final focusedContainer = tester.widget<AnimatedContainer>(
      find.ancestor(of: nameField, matching: find.byType(AnimatedContainer)),
    );
    final focusedBorder =
        (focusedContainer.decoration! as BoxDecoration).border;
    expect((focusedBorder! as Border).bottom.color, AppColors.primary);
  });

  testWidgets('auto-filled defaults follow the latest stable name match', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pump();

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '例如：牛奶、鸡蛋、番茄...',
    );

    await tester.enterText(nameField, '番茄');
    await tester.pump();

    expect(_selectedCategory(tester), FoodCategories.freshProduce);
    expect(_selectedStorage(tester), IconType.fridge);

    await tester.enterText(nameField, '番茄酱');
    await tester.pump();

    expect(_selectedCategory(tester), FoodCategories.other);
    expect(_selectedStorage(tester), IconType.pantry);
    expect(find.text('180天后过期'), findsOneWidget);
  });

  testWidgets('manual category changes are not overwritten by name changes', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pump();

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '例如：牛奶、鸡蛋、番茄...',
    );

    await tester.enterText(nameField, '番茄');
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(FoodCategories.meatAndSeafood).last);
    await tester.pumpAndSettle();

    await tester.enterText(nameField, '鸡蛋');
    await tester.pump();

    expect(_selectedCategory(tester), FoodCategories.meatAndSeafood);
  });

  testWidgets('dashboard add action no longer mentions scanning', (
    tester,
  ) async {
    final prefs = await _prefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          recentAdditionsProvider.overrideWithValue([]),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Dashboard no longer hosts the quick-add row — that surface was
    // redundant with the bottom nav center "+" FAB. Make sure none of
    // the legacy entry-mode labels (least of all 扫码) remain on it.
    expect(find.text('扫码'), findsNothing);
    expect(find.text('AI'), findsNothing);
    expect(find.text('拍照'), findsNothing);
    expect(find.text('手动'), findsNothing);
  });
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': '[]',
    'shopping_items': '[]',
    'add_history': '{}',
  });
  return SharedPreferences.getInstance();
}

String _selectedCategory(WidgetTester tester) {
  return tester
      .widget<DropdownButton<String>>(find.byType(DropdownButton<String>).first)
      .value!;
}

IconType _selectedStorage(WidgetTester tester) {
  return tester
      .widget<DropdownButton<IconType>>(find.byType(DropdownButton<IconType>))
      .value!;
}
