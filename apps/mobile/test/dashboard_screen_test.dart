import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/dashboard_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

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

  testWidgets('hero shows 已过期 label for expired items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _app(
        inventory: [
          _ingredient('牛奶', state: FreshnessState.expired),
          _ingredient('鸡蛋', state: FreshnessState.expiringSoon),
        ],
        recipes: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已过期'), findsAtLeastNWidgets(1));
    // '即将过期' is also used as a pill label on expiring cards, so it can
    // legitimately appear more than once.
    expect(find.text('即将过期'), findsAtLeastNWidgets(1));
    expect(find.text('快过期'), findsNothing);
  });

  testWidgets('dashboard shows category empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _app(inventory: const [], recipes: const []));
    await tester.pumpAndSettle();

    expect(find.text('食材分类'), findsOneWidget);
    expect(find.text('还没有分类数据'), findsOneWidget);
  });

  testWidgets('dashboard category cards fit compact phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _app(
        inventory: [
          _ingredient('牛奶'),
          _ingredient('酸奶'),
          _ingredient('奶酪'),
          _ingredient('黄油'),
        ],
        recipes: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('食材分类'), findsOneWidget);
  });
}

Future<Widget> _app({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final db = newTestDatabase();
  addTearDown(db.close);

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...testStorageOverrides(
        database: db,
        inventory: inventory,
        shopping: const [],
        customRecipes: const [],
      ),
      recipesProvider.overrideWith((ref) async => recipes),
      householdSessionControllerProvider.overrideWith(
        (ref) => HouseholdSessionController(
          HouseholdGatewayStub(isAuthenticated: true),
        ),
      ),
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
