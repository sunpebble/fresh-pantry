import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'helpers/fake_notification_service.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'dashboard "该用了" action pushes ExpiringScreen with not-fresh items',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          _ingredient('黄瓜').toJson(),
          _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
        ]),
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider
                .overrideWithValue(FakeNotificationService()),
          ],
          child: const FreshPantryApp(),
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
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('黄瓜').toJson(),
        _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
        _ingredient('面包', state: FreshnessState.expired).toJson(),
        _ingredient('番茄', state: FreshnessState.expiringSoon).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
        ],
        child: const FreshPantryApp(),
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
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          '面包',
          state: FreshnessState.expired,
        ).copyWith(expiryLabel: '已过期2天').toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
        ],
        child: const FreshPantryApp(),
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
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('黄瓜').toJson(),
        _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
        _ingredient('面包', state: FreshnessState.expired).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    // FK hero: 56pt big number is the inventory total; mini stats split
    // the not-fresh items into urgent vs soon.
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('你的冰箱状态'), findsOneWidget);
    // The 3 mini-stat labels live on the hero; same words can repeat as
    // pill labels on ExpiringCard rows, so use findsAtLeastNWidgets.
    expect(find.text('快过期'), findsAtLeastNWidgets(1));
    expect(find.text('即将过期'), findsAtLeastNWidgets(1));
    expect(find.text('库存不足'), findsOneWidget);
  });

  testWidgets('discarding a new ingredient clears the form in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp();
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
