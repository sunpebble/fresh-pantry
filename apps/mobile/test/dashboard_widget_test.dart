import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/low_stock_screen.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'helpers/fake_notification_service.dart';
import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'dashboard "该用了" action pushes ExpiringScreen with not-fresh items',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final inventory = [
        _ingredient('黄瓜'),
        _ingredient('牛奶', state: FreshnessState.expiringSoon),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(
              database: db,
              inventory: inventory,
              shopping: const [],
            ),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            householdSessionControllerProvider.overrideWith(
              (ref) => HouseholdSessionController(
                HouseholdGatewayStub(isAuthenticated: true),
              ),
            ),
          ],
          child: const FreshPantryApp(home: AppShell()),
        ),
      );
      await tester.pumpAndSettle();

      // FK dashboard surfaces section "该用了" + actionLabel "全部";
      // tapping the action pushes ExpiringScreen.
      expect(find.text('该用了'), findsOneWidget);
      await tester.tap(find.text('全部').first);
      await tester.pumpAndSettle();

      expect(find.text('临期提醒'), findsOneWidget);
      // The expiring milk shows up grouped under "即将过期".
      expect(find.text('即将过期'), findsAtLeastNWidgets(1));
      expect(find.text('牛奶'), findsOneWidget);
      // The fresh cucumber is NOT in this view.
      expect(find.text('黄瓜'), findsNothing);
    },
  );

  testWidgets('dashboard 该用了 scroller renders every not-fresh item', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final inventory = [
      _ingredient('黄瓜'),
      _ingredient('牛奶', state: FreshnessState.expiringSoon),
      _ingredient('面包', state: FreshnessState.expired),
      _ingredient('番茄', state: FreshnessState.expiringSoon),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: inventory,
            shopping: const [],
          ),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // The FK 该用了 horizontal scroller renders one card per not-fresh item.
    // All three names must be present; the fresh cucumber must not be.
    expect(find.text('牛奶'), findsAtLeastNWidgets(1));
    expect(find.text('面包'), findsAtLeastNWidgets(1));
    expect(find.text('番茄'), findsAtLeastNWidgets(1));
    expect(find.text('黄瓜'), findsNothing);
  });

  testWidgets('dashboard 该用了 ExpiringCard uses expiryLabel as the pill', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final inventory = [
      _ingredient(
        '面包',
        state: FreshnessState.expired,
      ).copyWith(expiryLabel: '已过期2天'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: inventory,
            shopping: const [],
          ),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // The ExpiringCard surfaces the ingredient's expiryLabel verbatim — never
    // falls back to hard-coded labels like "今天" or "48H".
    expect(find.text('已过期2天'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('48H'), findsNothing);
  });

  testWidgets('dashboard hero shows the total inventory count', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final inventory = [
      _ingredient('黄瓜'),
      _ingredient('牛奶', state: FreshnessState.expiringSoon),
      _ingredient('面包', state: FreshnessState.expired),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: inventory,
            shopping: const [],
          ),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // FK hero: 56pt big number is the inventory total; mini stats split
    // the not-fresh items into urgent vs soon.
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('你的冰箱状态'), findsOneWidget);
    // The 3 mini-stat labels live on the hero; same words can repeat as
    // pill labels on ExpiringCard rows, so use findsAtLeastNWidgets.
    expect(find.text('已过期'), findsAtLeastNWidgets(1));
    expect(find.text('即将过期'), findsAtLeastNWidgets(1));
    expect(find.text('库存不足'), findsOneWidget);
  });

  testWidgets(
    'dashboard hero not-fresh stat opens fridge with not-fresh filter',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final inventory = [
        _ingredient('牛奶', state: FreshnessState.expiringSoon),
      ];
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(
              database: db,
              inventory: inventory,
              shopping: const [],
            ),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            householdSessionControllerProvider.overrideWith(
              (ref) => HouseholdSessionController(
                HouseholdGatewayStub(isAuthenticated: true),
              ),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const FreshPantryApp(home: AppShell());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('即将过期 1'));
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), FkTab.fridge);
      expect(container.read(selectedCategoryProvider), inventoryFilterNotFresh);
    },
  );

  testWidgets(
    'dashboard hero low-stock stat shows real count and opens low stock screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final repo = InventoryRepo(db);
      repo.hydrate(const []);
      await repo.saveHistory({
        '米': {
          'count': 5,
          'category': FoodCategories.other,
          'storage': 'pantry',
          'unit': '袋',
        },
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            inventoryRepoProvider.overrideWithValue(repo),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            householdSessionControllerProvider.overrideWith(
              (ref) => HouseholdSessionController(
                HouseholdGatewayStub(isAuthenticated: true),
              ),
            ),
          ],
          child: const FreshPantryApp(home: AppShell()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('库存不足 1'));
      await tester.pumpAndSettle();

      // 「库存不足」stat 现跳转到独立的 LowStockScreen(常买补货页)。
      expect(find.byType(LowStockScreen), findsOneWidget);
      expect(find.text('米'), findsOneWidget);
    },
  );

  testWidgets(
    'dashboard category tile opens fridge filtered to that category',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final inventory = [
        _ingredient('黄瓜').copyWith(category: FoodCategories.freshProduce),
        _ingredient('牛奶').copyWith(category: FoodCategories.dairyAndEggs),
      ];
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(
              database: db,
              inventory: inventory,
              shopping: const [],
            ),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            householdSessionControllerProvider.overrideWith(
              (ref) => HouseholdSessionController(
                HouseholdGatewayStub(isAuthenticated: true),
              ),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const FreshPantryApp(home: AppShell());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedCategoryProvider), inventoryFilterAll);

      await tester.ensureVisible(find.text('蔬菜'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('蔬菜'));
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), FkTab.fridge);
      expect(
        container.read(selectedCategoryProvider),
        FoodCategories.freshProduce,
      );
    },
  );

  testWidgets('discarding a new ingredient clears the form in place', (
    tester,
  ) async {
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
            inventory: const [],
            shopping: const [],
          ),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp(home: AppShell());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // FK bottom nav: tap "食材" tab then center primary "+" FAB.
    await tester.tap(find.text('食材'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('添加食材'));
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 2);
    expect(find.text('添加食材'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '牛奶');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '牛奶'), findsOneWidget);

    await tester.ensureVisible(find.text('丢弃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃').last);
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 2);
    expect(find.text('添加食材'), findsOneWidget);
    expect(find.widgetWithText(TextField, '牛奶'), findsNothing);
  });
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
    category: '测试',
    storage: IconType.fridge,
    expiryLabel: state == FreshnessState.fresh ? '新鲜' : '即将过期',
  );
}
