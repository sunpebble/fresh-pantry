import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/recipe_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_snackbar.dart';
import '../utils/dashboard_greeting.dart';
import '../widgets/dashboard/expiring_fallback_card.dart';
import '../widgets/dashboard/low_stock_card.dart';
import '../widgets/recipe_card.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_hero_header.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/fk_section_head.dart';
import 'expiring_screen.dart';
import 'recipe_detail_screen.dart';
import 'settings_screen.dart';

/// FreshKeeper 首页 — 设计稿 `screens-1.jsx::HomeScreen`。
///
/// 视觉栈:
/// 1. 渐变 Hero(问候 + 总数大数字 + 3-grid mini stats)
/// 2. Quick Add 浮卡 — overlap hero(扫码 / 拍照 / 手动 → Add tab)
/// 3. "该用了" 横滚 ExpiringCard
/// 4. "食材分类" 4-col grid
/// 5. "今日推荐" recipe card
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refreshDashboard(context, ref),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: const [
            _DashboardHero(),
            _ExpiringItemsSection(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: LowStockCard(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: ExpiringFallbackCard(),
            ),
            _CategorySection(),
            _TodayRecommendationSection(),
          ],
        ),
      ),
    );
  }
}

Future<void> _refreshDashboard(BuildContext context, WidgetRef ref) async {
  try {
    ref.invalidate(recipesProvider);
    await ref.read(recipesProvider.future);
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(context, '刷新推荐失败，请稍后重试', backgroundColor: AppColors.error);
  }
}

Map<String, int> _countByCategory(List<Ingredient> items) {
  final m = <String, int>{};
  for (final item in items) {
    final id = fkCategoryIdFor(item.category);
    m[id] = (m[id] ?? 0) + 1;
  }
  return m;
}

String _categoryCountsSignature(List<Ingredient> items) {
  final counts = _countByCategory(items);
  final entries =
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}:${entry.value}').join('|');
}

Future<void> _addToShoppingList(
  BuildContext context,
  WidgetRef ref,
  Ingredient item,
) async {
  final added = await ref
      .read(shoppingProvider.notifier)
      .addFromIngredient(item);
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
    backgroundColor: added ? AppColors.primary : AppColors.tertiary,
  );
}

class _DashboardHero extends ConsumerWidget {
  const _DashboardHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(inventoryProvider.select((items) => items.length));
    final categoryCount = ref.watch(
      inventoryProvider.select(
        (items) =>
            items.map((item) => fkCategoryIdFor(item.category)).toSet().length,
      ),
    );
    final expiringCounts = ref.watch(
      expiringItemsProvider.select(
        (items) => (
          urgent: items.where((i) => i.state == FreshnessState.expired).length,
          soon:
              items.where((i) => i.state == FreshnessState.expiringSoon).length,
        ),
      ),
    );

    return _HeroSection(
      greeting: dashboardGreetingFor(DateTime.now()),
      total: total,
      categoryCount: categoryCount,
      urgent: expiringCounts.urgent,
      soon: expiringCounts.soon,
      lowStock: 0,
      onSettings:
          () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
    );
  }
}

class _ExpiringItemsSection extends ConsumerWidget {
  const _ExpiringItemsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringItems = ref.watch(expiringItemsProvider);
    if (expiringItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FkSectionHead(
          title: '该用了',
          count: expiringItems.length,
          actionLabel: '全部',
          onAction:
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ExpiringScreen())),
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: expiringItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final item = expiringItems[i];
              return _ExpiringCard(
                item: item,
                onAdd: () => _addToShoppingList(context, ref, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(inventoryProvider.select(_categoryCountsSignature));
    final categoryCounts = _countByCategory(ref.read(inventoryProvider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FkSectionHead(
          title: '食材分类',
          actionLabel: '全部',
          onAction: () => ref.navigateToTab(FkTab.fridge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child:
              categoryCounts.isEmpty
                  ? const _DashboardEmptyState(
                    icon: Icons.category_outlined,
                    label: '还没有分类数据',
                  )
                  : _CategoryGrid(
                    counts: categoryCounts,
                    onTap: (cat) => ref.navigateToTab(FkTab.fridge),
                  ),
        ),
      ],
    );
  }
}

class _TodayRecommendationSection extends ConsumerWidget {
  const _TodayRecommendationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendedRecipes = ref.watch(recommendedRecipesProvider);
    if (recommendedRecipes.isEmpty) {
      return const SizedBox(height: 100);
    }

    ref.watch(inventoryProvider.select(inventoryNamesSignature));
    final inventoryNames = inventoryNameSet(ref.read(inventoryProvider));
    final todayRecipe = recommendedRecipes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FkSectionHead(
          title: '今日推荐',
          trailing: const FkPill(
            label: '智能推荐',
            backgroundColor: AppColors.primarySoft,
            foregroundColor: AppColors.primaryContainer,
            sm: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
          child: RecipeCard(
            recipe: todayRecipe,
            matchedCount: matchedIngredientCountForNames(
              inventoryNames,
              todayRecipe,
            ),
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecipeDetailScreen(recipe: todayRecipe),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: AppFontSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部 hero — 渐变背景 + 问候 + 大数字 stat + 3-grid mini stat。
class _HeroSection extends StatelessWidget {
  final String greeting;
  final int total;
  final int categoryCount;
  final int urgent;
  final int soon;
  final int lowStock;
  final VoidCallback onSettings;

  const _HeroSection({
    required this.greeting,
    required this.total,
    required this.categoryCount,
    required this.urgent,
    required this.soon,
    required this.lowStock,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return FkHeroHeader(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '你的冰箱状态',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              FkIconButton(
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                foregroundColor: Colors.white,
                onTap: onSettings,
                child: const Icon(Icons.notifications_outlined),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: AppTypography.heroStat.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '件食材 · $categoryCount 类',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '快过期',
                  count: urgent,
                  accent: AppColors.fkDanger,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: '即将过期',
                  count: soon,
                  accent: AppColors.fkWarn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: '库存不足',
                  count: lowStock,
                  accent: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int count;
  final Color accent;
  const _MiniStat({
    required this.label,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiringCard extends StatelessWidget {
  final Ingredient item;
  final VoidCallback onAdd;
  const _ExpiringCard({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final catId = fkCategoryIdFor(item.category);
    final palette = FkCategoryPalette.of(catId);
    final isExpired = item.state == FreshnessState.expired;
    final pillBg = isExpired ? AppColors.fkDanger : AppColors.fkWarnSoft;
    final pillFg = isExpired ? Colors.white : AppColors.onSecondaryContainer;
    final topBorder = isExpired ? AppColors.fkDanger : AppColors.fkWarn;

    return Container(
      width: 144,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
        border: Border(top: BorderSide(color: topBorder, width: 3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: CatIcon(category: catId, size: 36, color: palette.ink),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${item.quantity}${item.unit}',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (item.expiryLabel != null)
            FkPill(
              label: item.expiryLabel!,
              backgroundColor: pillBg,
              foregroundColor: pillFg,
              sm: true,
            ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final Map<String, int> counts;
  final void Function(String catId) onTap;
  const _CategoryGrid({required this.counts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.take(8).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final palette = FkCategoryPalette.of(entry.key);
        return GestureDetector(
          onTap: () => onTap(entry.key),
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: palette.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CatIcon(category: entry.key, size: 28, color: palette.ink),
                const SizedBox(height: 4),
                Text(
                  FkCategoryPalette.names[entry.key] ?? entry.key,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.value}',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: palette.ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
