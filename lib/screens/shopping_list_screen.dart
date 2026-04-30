import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../theme/app_theme.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/shopping_provider.dart';
import 'recipe_detail_screen.dart';
import '../widgets/common/swipe_reveal_delete_action.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shopping/quick_add_field.dart';
import '../widgets/shopping/shopping_item_tile.dart';
import '../widgets/shopping/smart_planner_card.dart';

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final Set<String> _collapsedCategories = <String>{};

  @override
  Widget build(BuildContext context) {
    final groupedItems = ref.watch(groupedShoppingProvider);
    final allItems = ref.watch(shoppingProvider);
    final checkedCount = ref.watch(checkedCountProvider);
    final uncheckedCount = ref.watch(uncheckedCountProvider);
    ref.listen<String?>(shoppingCategoryToExpandProvider, (previous, category) {
      if (category == null) return;
      if (_collapsedCategories.remove(category)) {
        setState(() {});
      }
      ref.read(shoppingCategoryToExpandProvider.notifier).state = null;
    });

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 800));
        },
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '购物清单',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$uncheckedCount 件待购 · $checkedCount 件已购',
                              style: GoogleFonts.manrope(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (checkedCount > 0)
                          GestureDetector(
                            onTap: () => _confirmClearChecked(context, ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cleaning_services_outlined,
                                    size: 16,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '清理已购',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Quick Add Section
                    const QuickAddField(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
            // Categorized items
            if (allItems.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 64,
                          color: AppColors.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '购物清单为空',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '在上方输入框添加需要购买的食材',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    for (final entry in groupedItems.entries)
                      _buildCategorySection(
                        context,
                        entry.key,
                        entry.value,
                        _collapsedCategories.contains(entry.key),
                        ref,
                      ),
                    SmartPlannerCard(
                      title: '再买2样食材，就能完成您的卡博纳拉意面食谱。',
                      recipeName: '卡博纳拉意面',
                      onViewRecipe: () => _openPlannerRecipe(context),
                    ),
                  ]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  void _openPlannerRecipe(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(recipe: MockData.recipes.first),
      ),
    );
  }

  void _confirmClearChecked(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '清理已购项目',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              '确定要移除所有已勾选的购物项吗？',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  final items = ref.read(shoppingProvider);
                  final checkedItems =
                      items.where((item) => item.isChecked).toList();
                  for (final item in checkedItems) {
                    ref.read(shoppingProvider.notifier).remove(item.id);
                  }
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已清理 ${checkedItems.length} 个已购项目'),
                      persist: false,
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
                child: Text(
                  '清理',
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _deleteShoppingItem(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) {
    ref.read(shoppingProvider.notifier).remove(item.id);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${item.name}」已删除'),
        persist: false,
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '撤销',
          textColor: AppColors.onError,
          onPressed: () {
            ref.read(shoppingProvider.notifier).add(item);
          },
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    String title,
    List<ShoppingItem> items,
    bool isCollapsed,
    WidgetRef ref,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: '$title，${items.length} 件',
            hint: isCollapsed ? '点击展开分类' : '点击折叠分类',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  if (isCollapsed) {
                    _collapsedCategories.remove(title);
                  } else {
                    _collapsedCategories.add(title);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    CategoryIconAvatar(
                      category: title,
                      size: 32,
                      iconSize: 18,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${items.length} 件',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child:
                isCollapsed
                    ? const SizedBox.shrink()
                    : Column(
                      children: [
                        const SizedBox(height: 12),
                        for (final item in items)
                          SwipeRevealDeleteAction(
                            key: ValueKey('shop_swipe_${item.id}'),
                            deleteButtonKey: ValueKey(
                              'shopping_swipe_delete_${item.id}',
                            ),
                            onDelete:
                                () => _deleteShoppingItem(context, ref, item),
                            child: ShoppingItemTile(
                              key: ValueKey(item.id),
                              item: item,
                              onTap: () => _onItemChecked(context, ref, item),
                            ),
                          ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  void _onItemChecked(BuildContext context, WidgetRef ref, ShoppingItem item) {
    final wasChecked = item.isChecked;
    ref.read(shoppingProvider.notifier).toggleCheck(item.id);

    // When checking off (not unchecking), offer to add to inventory
    if (!wasChecked) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${item.name}」已购买'),
          persist: false,
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          action: SnackBarAction(
            label: '加入库存',
            textColor: AppColors.onPrimary,
            onPressed: () {
              final defaults = FoodKnowledge.lookup(item.name);
              final now = DateTime.now();
              final expiryDate =
                  defaults != null
                      ? now.add(Duration(days: defaults.shelfLifeDays))
                      : null;
              final freshness = expiryDate != null ? 1.0 : 0.85;

              final ingredient = Ingredient(
                name: item.name,
                quantity: '1',
                unit: '份',
                imageUrl: item.imageUrl ?? '',
                freshnessPercent: freshness,
                state: FreshnessState.fresh,
                category: FoodKnowledge.categoryFor(item.name),
                storage: defaults?.storage ?? IconType.fridge,
                expiryDate: expiryDate,
                shelfLifeDays: defaults?.shelfLifeDays,
                expiryLabel:
                    expiryDate != null
                        ? '${defaults!.shelfLifeDays}天后过期'
                        : '新鲜',
              );

              ref.read(inventoryProvider.notifier).add(ingredient);

              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已添加「${item.name}」到库存'),
                  persist: false,
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
  }
}
