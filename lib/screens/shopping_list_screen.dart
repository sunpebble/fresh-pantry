import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';
import '../providers/inventory_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_top_bar.dart';
import '../widgets/shopping/quick_add_field.dart';
import '../widgets/shopping/smart_planner_card.dart';
import 'recipe_detail_screen.dart';

/// FreshKeeper 购物清单 — 设计稿 `screens-3.jsx::ShoppingScreen`。
///
/// FK top bar + 大渐变进度卡(本次采购进度 + 大数字 done/total + percent + 白色
/// 进度条)+ 待购/已购 filter chip + 按品类分组 FkCard(每行圆形 check + 名称 +
/// detail + 删除 icon)+ 清空已完成 dashed CTA。
enum _ShoppingFilter { all, todo, done }

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  _ShoppingFilter _filter = _ShoppingFilter.all;
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

    final total = allItems.length;
    final done = checkedCount;
    final progress = total == 0 ? 0.0 : done / total;

    final visibleGroups = _applyFilter(groupedItems);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: RefreshIndicator(
        onRefresh: () async =>
            await Future.delayed(const Duration(milliseconds: 600)),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: FkTopBar(
                  title: '购物清单',
                  subtitle: total == 0
                      ? '清单为空 · 在上方添加食材'
                      : '$done/$total 已完成 · $uncheckedCount 件待购',
                  actions: [
                    FkIconButton(
                      child: const Icon(Icons.add_rounded, size: 18),
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.requestFocus(),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _ProgressCard(done: done, total: total, progress: progress),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: const QuickAddField(),
              ),
            ),
            SliverToBoxAdapter(
              child: _FilterChipRow(
                selected: _filter,
                todoCount: uncheckedCount,
                doneCount: checkedCount,
                onSelect: (f) => setState(() => _filter = f),
              ),
            ),
            if (allItems.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    for (final entry in visibleGroups.entries)
                      _CategoryGroup(
                        title: entry.key,
                        items: entry.value,
                        collapsed: _collapsedCategories.contains(entry.key),
                        onToggleCollapse: () => setState(() {
                          if (_collapsedCategories.contains(entry.key)) {
                            _collapsedCategories.remove(entry.key);
                          } else {
                            _collapsedCategories.add(entry.key);
                          }
                        }),
                        onItemToggle: (item) => _onItemChecked(context, ref, item),
                        onItemDelete: (item) =>
                            _deleteShoppingItem(context, ref, item),
                      ),
                    if (visibleGroups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Center(
                          child: Text(
                            _filter == _ShoppingFilter.todo
                                ? '没有待购项目'
                                : '没有已购项目',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if (allItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SmartPlannerCard(
                          title: '再买2样食材，就能完成您的卡博纳拉意面食谱。',
                          onViewRecipe: () => _openPlannerRecipe(context),
                        ),
                      ),
                    if (checkedCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _ClearDoneButton(
                          count: checkedCount,
                          onTap: () => _confirmClearChecked(context, ref),
                        ),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, List<ShoppingItem>> _applyFilter(
    Map<String, List<ShoppingItem>> grouped,
  ) {
    if (_filter == _ShoppingFilter.all) return grouped;
    final result = <String, List<ShoppingItem>>{};
    grouped.forEach((cat, items) {
      final filtered = items
          .where(
            (i) =>
                _filter == _ShoppingFilter.todo ? !i.isChecked : i.isChecked,
          )
          .toList();
      if (filtered.isNotEmpty) result[cat] = filtered;
    });
    return result;
  }

  void _openPlannerRecipe(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(recipe: MockData.recipes.first),
      ),
    );
  }

  Future<void> _confirmClearChecked(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清理已购项目',
      content: '确定要移除所有已勾选的购物项吗？',
      confirmLabel: '清理',
    );
    if (!confirmed || !context.mounted) return;
    final items = ref.read(shoppingProvider);
    final checkedItems = items.where((item) => item.isChecked).toList();
    for (final item in checkedItems) {
      ref.read(shoppingProvider.notifier).remove(item.id);
    }
    showAppSnackBar(
      context,
      '已清理 ${checkedItems.length} 个已购项目',
      backgroundColor: AppColors.primary,
    );
  }

  void _deleteShoppingItem(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) {
    ref.read(shoppingProvider.notifier).remove(item.id);
    showAppSnackBar(
      context,
      '「${item.name}」已删除',
      backgroundColor: AppColors.error,
      actionLabel: '撤销',
      actionTextColor: AppColors.onError,
      onAction: () {
        ref.read(shoppingProvider.notifier).add(item);
      },
    );
  }

  void _onItemChecked(BuildContext context, WidgetRef ref, ShoppingItem item) {
    final wasChecked = item.isChecked;
    ref.read(shoppingProvider.notifier).toggleCheck(item.id);
    if (!wasChecked) {
      showAppSnackBar(
        context,
        '「${item.name}」已购买',
        backgroundColor: AppColors.primary,
        actionLabel: '加入库存',
        actionTextColor: AppColors.onPrimary,
        onAction: () => _addItemToInventory(item.name, item.imageUrl),
      );
    }
  }

  void _addItemToInventory(String name, String? imageUrl) {
    final defaults = FoodKnowledge.lookup(name);
    final now = DateTime.now();
    final expiryDate = defaults != null
        ? now.add(Duration(days: defaults.shelfLifeDays))
        : null;
    final freshness = expiryDate != null ? 1.0 : 0.85;
    final ingredient = Ingredient(
      name: name,
      quantity: '1',
      unit: '份',
      imageUrl: imageUrl ?? '',
      freshnessPercent: freshness,
      state: FreshnessState.fresh,
      category: FoodKnowledge.categoryFor(name),
      storage: defaults?.storage ?? IconType.fridge,
      expiryDate: expiryDate,
      shelfLifeDays: defaults?.shelfLifeDays,
      expiryLabel:
          expiryDate != null ? '${defaults!.shelfLifeDays}天后过期' : '新鲜',
    );
    ref.read(inventoryProvider.notifier).add(ingredient);
    showAppSnackBar(
      context,
      '已添加「$name」到库存',
      backgroundColor: AppColors.primary,
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int done;
  final int total;
  final double progress;
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return FkCard(
      padding: const EdgeInsets.all(16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.primaryContainer],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本次采购进度',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$done',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ $total 项',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  final _ShoppingFilter selected;
  final int todoCount;
  final int doneCount;
  final void Function(_ShoppingFilter) onSelect;
  const _FilterChipRow({
    required this.selected,
    required this.todoCount,
    required this.doneCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <(String, _ShoppingFilter, int)>[
      ('全部', _ShoppingFilter.all, todoCount + doneCount),
      ('待购买', _ShoppingFilter.todo, todoCount),
      ('已购', _ShoppingFilter.done, doneCount),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, value, count) = chips[i];
          final active = value == selected;
          return GestureDetector(
            onTap: () => onSelect(value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.hair,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 0 ? '$label · $count' : label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  final String title;
  final List<ShoppingItem> items;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final void Function(ShoppingItem) onItemToggle;
  final void Function(ShoppingItem) onItemDelete;

  const _CategoryGroup({
    required this.title,
    required this.items,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onItemToggle,
    required this.onItemDelete,
  });

  @override
  Widget build(BuildContext context) {
    final catId = fkCategoryIdFor(title);
    final palette = FkCategoryPalette.of(catId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: '$title，${items.length} 件',
            hint: collapsed ? '点击展开分类' : '点击折叠分类',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleCollapse,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    CatIcon(category: catId, size: 20, color: palette.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${items.length}',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
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
            child: collapsed
                ? const SizedBox.shrink()
                : FkCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          _ShopRow(
                            item: items[i],
                            isLast: i == items.length - 1,
                            onToggle: () => onItemToggle(items[i]),
                            onDelete: () => onItemDelete(items[i]),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShopRow extends StatelessWidget {
  final ShoppingItem item;
  final bool isLast;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ShopRow({
    required this.item,
    required this.isLast,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final checked = item.isChecked;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.hair, width: 0.5),
                ),
        ),
        child: Opacity(
          opacity: checked ? 0.45 : 1.0,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: checked ? AppColors.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: checked ? AppColors.primary : AppColors.hair,
                    width: 2,
                  ),
                ),
                child: checked
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        decoration: checked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (item.detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.detail,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearDoneButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ClearDoneButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.hair,
            style: BorderStyle.solid,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '清空已完成 ($count)',
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_outlined,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '购物清单为空',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '在上方输入框添加需要购买的食材',
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
