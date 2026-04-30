import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/recipe_provider.dart';
import '../utils/dashboard_greeting.dart';
import '../widgets/dashboard/stat_card.dart';
import '../widgets/dashboard/alert_card.dart';
import '../widgets/dashboard/quick_action_card.dart';
import '../widgets/dashboard/storage_summary_card.dart';
import '../widgets/dashboard/recent_addition_item.dart';
import '../widgets/dashboard/curators_tip_card.dart';
import '../widgets/recipe_card.dart';
import '../widgets/shared/category_icon.dart';
import 'my_recipes_screen.dart';
import 'recipe_detail_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statCountsProvider);
    final expiringItems = ref.watch(expiringItemsProvider);
    final uncheckedCount = ref.watch(uncheckedCountProvider);
    final recentItems = ref.watch(recentAdditionsProvider);
    final recommendedRecipes = ref.watch(recommendedRecipesProvider);
    final storageAreas = ref.watch(storageAreasProvider);
    final now = DateTime.now();
    final quickActions = Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: QuickActionCard(
                  icon: Icons.add_circle,
                  title: '添加新食材',
                  subtitle: '手动录入食材',
                  backgroundColor: AppColors.primary,
                  contentColor: AppColors.onPrimary,
                  onTap: () {
                    ref.navigateToTab(2);
                  },
                  semanticLabel: '添加新食材，手动录入食材',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickActionCard(
                  icon: Icons.shopping_basket,
                  title: '购物清单',
                  subtitle: '还需$uncheckedCount件',
                  backgroundColor: AppColors.tertiaryFixedDim,
                  contentColor: AppColors.onTertiaryFixedDim,
                  onTap: () {
                    ref.navigateToTab(3);
                  },
                  semanticLabel: '购物清单，还需$uncheckedCount件',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RecipeShortcutTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyRecipesScreen()),
            );
          },
        ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 800));
      },
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ──
            Text(
              dashboardGreetingFor(now),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              dashboardSubtitleFor(now),
              style: GoogleFonts.manrope(
                fontSize: 16,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // ── Stats ──
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    value: '${stats.total}',
                    label: '种食材',
                    semanticLabel: '查看全部食材库存',
                    onTap: () {
                      ref.read(selectedCategoryProvider.notifier).state =
                          inventoryFilterAll;
                      ref.navigateToTab(1);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StatCard(
                    value: '${stats.expiringSoon}',
                    label: '即将过期',
                    isWarning: true,
                    semanticLabel: '查看即将过期食材',
                    onTap: () {
                      ref.read(selectedCategoryProvider.notifier).state =
                          inventoryFilterNotFresh;
                      ref.navigateToTab(1);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Quick Actions ──
            quickActions,
            const SizedBox(height: 24),

            // ── Urgent Attention (wrapped container) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.urgentAttentionBackground.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.priority_high,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '紧急关注',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final (index, item) in expiringItems.indexed)
                    Padding(
                      key: ValueKey('alert_$index'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AlertCard(
                        key: ValueKey('alert_card_$index'),
                        icon: _iconForCategory(item.category),
                        iconColor:
                            item.state == FreshnessState.expired
                                ? AppColors.secondary
                                : AppColors.primary,
                        name: item.name,
                        subtitle: item.expiryLabel ?? '即将过期',
                        storageTag: _storageLabel(item.storage),
                        badge: item.expiryLabel ?? '即将过期',
                        badgeBg:
                            item.state == FreshnessState.expired
                                ? AppColors.secondaryContainer
                                : AppColors.surfaceContainerHigh,
                        badgeText:
                            item.state == FreshnessState.expired
                                ? AppColors.onSecondaryContainer
                                : AppColors.onSurfaceVariant,
                        onConsume: () {
                          final idx = inventoryIndexOf(
                            ref.read(inventoryProvider),
                            item,
                          );
                          if (idx >= 0) {
                            ref.read(inventoryProvider.notifier).remove(idx);
                          }
                        },
                        onAddToCart: () {
                          _addToShoppingList(context, ref, item);
                        },
                      ),
                    ),
                  if (expiringItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Text(
                        '暂无需要紧急关注的食材',
                        style: GoogleFonts.manrope(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        button: true,
                        label: '食谱推荐',
                        child: GestureDetector(
                          onTap: () => _showRecipeSheet(context, ref),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '食谱推荐',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward,
                                  color: AppColors.onPrimary,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Storage Summary ──
            Text(
              '存储概况',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),
            for (final (index, area) in storageAreas.indexed)
              Padding(
                key: ValueKey('storage_$index'),
                padding: const EdgeInsets.only(bottom: 16),
                child: StorageSummaryCard(
                  key: ValueKey('storage_card_$index'),
                  area: area,
                ),
              ),
            const SizedBox(height: 24),

            // ── Recent Additions ──
            Text(
              '最近添加',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            for (final (index, item) in recentItems.indexed)
              RecentAdditionItem(key: ValueKey('recent_$index'), item: item),
            const SizedBox(height: 24),

            // ── Curator's Tip ──
            if (recommendedRecipes.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => RecipeDetailScreen(
                            recipe: recommendedRecipes.first,
                          ),
                    ),
                  );
                },
                child: CuratorsTipCard(
                  tip:
                      '根据您的库存，推荐制作「${recommendedRecipes.first.name}」——${recommendedRecipes.first.description}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForCategory(String? category) {
    return categoryIconFor(category);
  }

  String _storageLabel(IconType storage) {
    return switch (storage) {
      IconType.fridge => '冰箱',
      IconType.pantry => '食品柜',
    };
  }

  Future<void> _addToShoppingList(
    BuildContext context,
    WidgetRef ref,
    Ingredient item,
  ) async {
    final added = await ref
        .read(shoppingProvider.notifier)
        .add(
          ShoppingItem(
            id: 'si_${DateTime.now().millisecondsSinceEpoch}',
            name: item.name,
            detail: '${item.quantity} ${item.unit}',
            category: item.category ?? '其他',
          ),
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
        ),
        persist: false,
        backgroundColor: added ? AppColors.primary : AppColors.tertiary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showRecipeSheet(BuildContext context, WidgetRef ref) {
    final recipes = ref.read(recommendedRecipesProvider);
    final inventory = ref.read(inventoryProvider);
    final rootNavigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '食谱推荐',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '根据您的库存食材智能推荐',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: recipes.length,
                      itemBuilder: (_, index) {
                        final recipe = recipes[index];
                        final matched = matchedIngredientCount(
                          inventory,
                          recipe,
                        );
                        return RecipeCard(
                          recipe: recipe,
                          matchedCount: matched,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            rootNavigator.push(
                              MaterialPageRoute(
                                builder:
                                    (_) => RecipeDetailScreen(recipe: recipe),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RecipeShortcutTile extends StatelessWidget {
  final VoidCallback onTap;

  const _RecipeShortcutTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '我的食谱，添加和管理私房菜单',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.menu_book_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的食谱',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '添加和管理私房菜单',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.outline,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
