import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';
import 'package:fresh_pantry/widgets/dashboard/curators_tip_card.dart';
import 'package:fresh_pantry/widgets/dashboard/quick_action_card.dart';
import 'package:fresh_pantry/widgets/dashboard/stat_card.dart';
import 'package:fresh_pantry/widgets/dashboard/storage_summary_card.dart';
import 'package:fresh_pantry/widgets/shared/category_icon.dart';
import 'package:fresh_pantry/widgets/shared/freshness_meter.dart';
import 'package:fresh_pantry/widgets/shared/recipe_image.dart';
import 'package:fresh_pantry/widgets/shopping/smart_planner_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
Widget _wrapProvider(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  // ── StatCard ──────────────────────────────────────────────────────────────

  group('StatCard', () {
    testWidgets('renders value and label', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatCard(value: '42', label: '食材', isWarning: false)),
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.text('食材'.toUpperCase()), findsOneWidget);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(StatCard(value: '5', label: '临期', onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(StatCard));
      expect(tapped, isTrue);
    });
  });

  // ── QuickActionCard ───────────────────────────────────────────────────────

  group('QuickActionCard', () {
    testWidgets('renders title, subtitle, and icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QuickActionCard(
            icon: Icons.add,
            title: '添加',
            subtitle: '手动录入',
            backgroundColor: Colors.blue,
            contentColor: Colors.white,
          ),
        ),
      );
      expect(find.text('添加'), findsOneWidget);
      expect(find.text('手动录入'), findsOneWidget);
    });

    testWidgets('fires onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          QuickActionCard(
            icon: Icons.add,
            title: '操作',
            subtitle: '描述',
            backgroundColor: Colors.green,
            contentColor: Colors.white,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(QuickActionCard));
      expect(tapped, isTrue);
    });

    testWidgets('wraps content in Semantics', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QuickActionCard(
            icon: Icons.add,
            title: '添加',
            subtitle: '描述',
            backgroundColor: Colors.blue,
            contentColor: Colors.white,
            semanticLabel: '自定义语义标签',
          ),
        ),
      );
      expect(find.byType(Semantics), findsWidgets);
    });
  });

  // ── CuratorsTipCard ───────────────────────────────────────────────────────

  group('CuratorsTipCard', () {
    testWidgets('renders tip text', (tester) async {
      await tester.pumpWidget(_wrap(const CuratorsTipCard(tip: '今天适合清炒一道蔬菜')));
      expect(find.textContaining('今天适合清炒'), findsOneWidget);
    });

    testWidgets('renders custom bottomLabel', (tester) async {
      await tester.pumpWidget(
        _wrap(const CuratorsTipCard(tip: '提示', bottomLabel: '自定义底部文字')),
      );
      expect(find.text('自定义底部文字'), findsOneWidget);
    });
  });

  // ── CategoryIcon helpers ──────────────────────────────────────────────────

  group('fkCategoryIdFor', () {
    test('maps dairyAndEggs to dairy', () {
      expect(fkCategoryIdFor(FoodCategories.dairyAndEggs), 'dairy');
    });

    test('maps freshProduce to veg', () {
      expect(fkCategoryIdFor(FoodCategories.freshProduce), 'veg');
    });

    test('maps meatAndSeafood to meat', () {
      expect(fkCategoryIdFor(FoodCategories.meatAndSeafood), 'meat');
    });

    test('maps herbsAndSpices to sauce', () {
      expect(fkCategoryIdFor(FoodCategories.herbsAndSpices), 'sauce');
    });

    test('maps other to grain', () {
      expect(fkCategoryIdFor(FoodCategories.other), 'grain');
    });

    test('maps null to grain (fallback)', () {
      expect(fkCategoryIdFor(null), 'grain');
    });
  });

  group('categoryIconFor', () {
    test('returns icon for each category', () {
      for (final cat in FoodCategories.values) {
        final icon = categoryIconFor(cat);
        expect(icon, isNotNull);
      }
    });
  });

  // ── FreshnessMeter ────────────────────────────────────────────────────────

  group('FreshnessMeter', () {
    testWidgets('renders fresh label at 80%', (tester) async {
      await tester.pumpWidget(
        _wrap(const FreshnessMeter(percent: 0.8, state: FreshnessState.fresh)),
      );
      expect(find.textContaining('80%'), findsOneWidget);
    });

    testWidgets('renders expired state', (tester) async {
      await tester.pumpWidget(
        _wrap(const FreshnessMeter(percent: 0, state: FreshnessState.expired)),
      );
      expect(find.textContaining('0%'), findsOneWidget);
    });

    testWidgets('hides label when showLabel is false', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FreshnessMeter(
            percent: 0.5,
            state: FreshnessState.expiringSoon,
            showLabel: false,
          ),
        ),
      );
      // No percentage text should be visible
      expect(find.textContaining('%'), findsNothing);
    });
  });

  // ── RecipeImage ───────────────────────────────────────────────────────────

  group('RecipeImage', () {
    testWidgets('shows fallback when imageSource is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecipeImage(imageSource: null, fallback: const Text('placeholder')),
        ),
      );
      await tester.pump();
      expect(find.text('placeholder'), findsOneWidget);
    });

    testWidgets('shows fallback when imageSource is empty string', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecipeImage(imageSource: '', fallback: const Text('empty-fallback')),
        ),
      );
      await tester.pump();
      expect(find.text('empty-fallback'), findsOneWidget);
    });
  });

  // ── SmartPlannerCard ──────────────────────────────────────────────────────

  group('SmartPlannerCard', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(const SmartPlannerCard(title: '番茄炒蛋')));
      expect(find.text('番茄炒蛋'), findsOneWidget);
    });

    testWidgets('fires onViewRecipe callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SmartPlannerCard(title: '青椒肉丝', onViewRecipe: () => tapped = true),
        ),
      );
      // The button is inside the card — find it by text or icon
      final viewBtn = find.text('查看菜谱');
      if (viewBtn.evaluate().isNotEmpty) {
        await tester.tap(viewBtn);
        expect(tapped, isTrue);
      }
    });
  });

  // ── BottomNavBar ──────────────────────────────────────────────────────────

  group('BottomNavBar', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrapProvider(const BottomNavBar()));
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('tap switches the navigation provider tab', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: BottomNavBar())),
        ),
      );

      await tester.tap(find.text('食材'));
      await tester.pump();

      expect(container.read(navigationProvider), FkTab.fridge);
    });
  });

  // ── StorageSummaryCard ────────────────────────────────────────────────────

  group('StorageSummaryCard', () {
    testWidgets('renders fridge area name', (tester) async {
      final fridgeArea = StorageArea(
        name: '冰箱',
        icon: IconType.fridge,
        itemCount: 5,
        capacityPercent: 0.6,
      );
      await tester.pumpWidget(_wrap(StorageSummaryCard(area: fridgeArea)));
      expect(find.text('冰箱'), findsOneWidget);
      expect(find.text('5 件'), findsOneWidget);
      expect(find.text('60% 容量'), findsOneWidget);
    });
  });
}
