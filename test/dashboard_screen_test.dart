import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'dashboard renders hero, expiring, category, and recommendation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await _app(
          inventory: [
            _ingredient('牛奶', state: FreshnessState.expiringSoon),
            _ingredient('鸡蛋'),
          ],
          recipes: [_recipe()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('你的冰箱状态'), findsOneWidget);
      expect(find.text('该用了'), findsOneWidget);
      expect(find.text('食材分类'), findsOneWidget);
      expect(find.text('今日推荐'), findsOneWidget);
      expect(find.text('牛奶早餐杯'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('全部').first);
      await tester.pumpAndSettle();

      expect(find.text('临期提醒'), findsOneWidget);
      expect(find.text('牛奶'), findsOneWidget);
    },
  );

  testWidgets('dashboard shows category empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _app(inventory: const [], recipes: const []));
    await tester.pumpAndSettle();

    expect(find.text('食材分类'), findsOneWidget);
    expect(find.text('还没有分类数据'), findsOneWidget);
  });
}

Future<Widget> _app({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({
    'shopping_items': '[]',
    'custom_recipes': '[]',
  });
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(inventory),
      recipesProvider.overrideWith((ref) async => recipes),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: false),
      home: const Scaffold(body: DashboardScreen()),
    ),
  );
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
    category: '乳制品',
    storage: IconType.fridge,
    expiryLabel: state == FreshnessState.fresh ? '新鲜' : '即将过期',
  );
}

Recipe _recipe() {
  return Recipe(
    id: 'recipe-milk',
    name: '牛奶早餐杯',
    category: '早餐',
    difficulty: 1,
    cookingMinutes: 10,
    description: '使用现有牛奶',
    ingredients: [RecipeIngredient(name: '牛奶', amount: '1杯')],
    steps: const ['倒入杯中'],
  );
}
