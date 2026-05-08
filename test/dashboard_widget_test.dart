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
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/widgets/dashboard/alert_card.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'dashboard expiring overview opens inventory with not fresh filter',
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
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
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

      await tester.tap(find.text('即将过期').first);
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), 1);
      expect(container.read(selectedCategoryProvider), '不新鲜');
      expect(
        container.read(filteredByCategoryProvider).map((item) => item.name),
        ['牛奶'],
      );
    },
  );

  testWidgets('dashboard urgent attention shows every not fresh item', (
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
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('牛奶')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('面包')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('番茄')),
      findsOneWidget,
    );
  });

  testWidgets(
    'dashboard urgent attention uses the item expiry label as badge',
    (tester) async {
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
          ],
          child: const FreshPantryApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The AlertCard renders the ingredient's expiryLabel — both as
      // subtitle text and as the badge — and never falls back to
      // hard-coded labels like "今天" or "48H".
      expect(
        find.descendant(
          of: find.byType(AlertCard),
          matching: find.text('已过期2天'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(AlertCard),
          matching: find.text('今天'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertCard),
          matching: find.text('48H'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('alert cards keep actions visible on narrow dashboard widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AlertCard(
                icon: Icons.kitchen,
                iconColor: Colors.green,
                name: '牛奶',
                subtitle: '已过期2天',
                storageTag: '冰箱',
                badge: '已过期2天',
                badgeBg: Colors.orange,
                badgeText: Colors.black,
                onConsume: () {},
                onAddToCart: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('已消耗'), findsOneWidget);
    expect(find.text('加入清单'), findsOneWidget);
    expect(find.text('已过期2天'), findsWidgets);
  });

  testWidgets('dashboard total overview resets inventory filter to all', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('黄瓜').toJson(),
        _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
      ]),
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
          selectedCategoryProvider.overrideWith((ref) => '不新鲜'),
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

    await tester.tap(find.text('种食材'));
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 1);
    expect(container.read(selectedCategoryProvider), '全部');
    expect(
      container.read(filteredByCategoryProvider).map((item) => item.name),
      ['黄瓜', '牛奶'],
    );
  });

  testWidgets('dashboard storage overview omits view all shortcut', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('存储概况'), findsOneWidget);
    expect(find.text('查看全部'), findsNothing);
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

    await tester.tap(find.text('库存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 2);
    expect(find.text('策划您的食材库'), findsOneWidget);

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
    expect(find.text('策划您的食材库'), findsOneWidget);
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
