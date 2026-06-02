import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/shopping_item.dart';
import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../services/intake_proposal_factory.dart';
import 'intake_review_screen.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/page_transitions.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_empty_state.dart';
import '../widgets/shared/fk_entrance.dart';
import '../widgets/shared/fk_dashed_border.dart';
import '../widgets/shared/fk_top_bar.dart';
import '../widgets/shopping/quick_add_field.dart';

/// FreshKeeper 购物清单 - 设计稿 `screens-3.jsx::ShoppingScreen`。
///
/// FK top bar + 大渐变进度卡(本次采购进度 + 大数字 done/total + percent + 白色
/// 进度条)+ 待购/已购 filter chip + 按品类分组 FkCard(每行圆形 check + 名称 +
/// detail + 删除 icon)+ 清空已完成 dashed CTA。
class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(shoppingListViewProvider);
    final collapsedCategories = ref.watch(collapsedShoppingCategoriesProvider);
    final allItems = viewState.items;
    final total = viewState.total;
    final checkedCount = viewState.checkedCount;
    final uncheckedCount = viewState.uncheckedCount;
    final visibleEntries = viewState.visibleGroups.entries.toList(
      growable: false,
    );
    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: () => _refreshShoppingList(context, ref),
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
                          : '$checkedCount/$total 已完成 · $uncheckedCount 件待购',
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _ProgressCard(
                      done: checkedCount,
                      total: total,
                      progress: viewState.progress,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      18,
                      14,
                      18,
                      AppSpacing.sm,
                    ),
                    child: const QuickAddField(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _FilterChipRow(
                    selected: viewState.filter,
                    todoCount: uncheckedCount,
                    doneCount: checkedCount,
                    onSelect: (filter) =>
                        ref.read(shoppingFilterProvider.notifier).state =
                            filter,
                  ),
                ),
                if (allItems.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: FkEntrance(
                      child: FkEmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: '购物清单为空',
                        subtitle: '在上方输入框添加需要购买的食材',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
                    sliver: _ShoppingContentSliver(
                      visibleEntries: visibleEntries,
                      selectedFilter: viewState.filter,
                      collapsedCategories: collapsedCategories,
                      checkedCount: checkedCount,
                      onToggleCategory: (category) =>
                          _toggleCategory(ref, category),
                      onItemToggle: (item) =>
                          _onItemChecked(context, ref, item),
                      onItemDelete: (item) =>
                          _deleteShoppingItem(context, ref, item),
                      onClearChecked: () => _confirmClearChecked(context, ref),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (checkedCount > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: FilledButton(
                key: const Key('shopping_to_intake_cta'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => _openIntakeReviewForChecked(context, ref),
                child: Text('已购买的 $checkedCount 项一键入库'),
              ),
            ),
          ),
      ],
    );
  }

  void _toggleCategory(WidgetRef ref, String category) {
    ref.read(collapsedShoppingCategoriesProvider.notifier).update((collapsed) {
      final next = {...collapsed};
      if (!next.add(category)) {
        next.remove(category);
      }
      return next;
    });
  }

  Future<void> _refreshShoppingList(BuildContext context, WidgetRef ref) async {
    try {
      ref.invalidate(shoppingProvider);
      ref.invalidate(shoppingListViewProvider);
      ref.read(shoppingListViewProvider);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry.shopping',
          context: ErrorDescription('while refreshing shopping list'),
        ),
      );
      if (!context.mounted) return;
      showAppSnackBar(context, '购物清单刷新失败', backgroundColor: AppColors.error);
    }
  }

  Future<void> _confirmClearChecked(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清理已购项目',
      content: '确定要移除所有已勾选的购物项吗？',
      confirmLabel: '清理',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final items = ref.read(shoppingProvider);
    final checkedItems = items.where((item) => item.isChecked).toList();
    final notifier = ref.read(shoppingProvider.notifier);
    var removed = 0;
    for (final item in checkedItems) {
      try {
        await notifier.remove(item.id);
        removed++;
      } catch (_) {
        // Keep clearing the rest; the snackbar reports the real removed count.
      }
    }
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      removed == checkedItems.length
          ? '已清理 $removed 个已购项目'
          : '已清理 $removed/${checkedItems.length} 个，部分失败请重试',
      backgroundColor: removed == 0 ? AppColors.error : AppColors.primary,
    );
  }

  Future<void> _deleteShoppingItem(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) async {
    try {
      await ref.read(shoppingProvider.notifier).remove(item.id);
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, '删除失败，请重试');
      return;
    }
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      '「${item.name}」已删除',
      backgroundColor: AppColors.error,
      actionLabel: '撤销',
      actionTextColor: AppColors.onError,
      onAction: () async {
        try {
          await ref.read(shoppingProvider.notifier).add(item);
        } catch (_) {
          if (context.mounted) showAppSnackBar(context, '撤销失败，请重试');
        }
      },
    );
  }

  Future<void> _onItemChecked(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) async {
    final wasChecked = item.isChecked;
    try {
      await ref.read(shoppingProvider.notifier).toggleCheck(item.id);
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, '操作失败，请重试');
      return;
    }
    if (!context.mounted) return;
    if (!wasChecked) {
      showAppSnackBar(
        context,
        '「${item.name}」已购买',
        backgroundColor: AppColors.primary,
        actionLabel: '加入库存',
        actionTextColor: AppColors.onPrimary,
        onAction: () => _addItemToInventory(context, ref, item),
      );
    }
  }

  Future<void> _openIntakeReviewForChecked(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final all = ref.read(shoppingProvider);
    final checked = all.where((i) => i.isChecked).toList();
    if (checked.isEmpty) return;

    final inventory = ref.read(inventoryProvider);
    final proposals = IntakeProposalFactory.fromShoppingItems(
      checked,
      inventory,
    );
    ref.read(intakeReviewProvider.notifier).seed(proposals);

    final appliedIds = await Navigator.of(context).push<Set<String>>(
      fkRoute<Set<String>>(
        builder: (_) => const IntakeReviewScreen(title: '已购买项入库'),
      ),
    );

    // Remove ONLY the checked items whose intake proposal was actually applied
    // (proposal id is `ix_<itemId>`). A cancelled review or a deselected
    // proposal returns no id for that item, so it stays on the list instead of
    // being silently discarded without ever entering inventory.
    if (!context.mounted) return;
    if (appliedIds == null || appliedIds.isEmpty) return;
    final shopping = ref.read(shoppingProvider.notifier);
    for (final item in checked) {
      if (appliedIds.contains('ix_${item.id}')) {
        try {
          await shopping.remove(item.id);
        } catch (_) {
          // Item entered inventory but couldn't be cleared from the list;
          // leave it checked so a later attempt can retry the removal.
        }
      }
    }
  }

  Future<void> _addItemToInventory(
    BuildContext context,
    WidgetRef ref,
    ShoppingItem item,
  ) async {
    // 走与"一键入库"完全相同的审核流程,确保数量解析、批次合并与"应用后从
    // 清单移除"的语义一致(此前快捷入库写死 数量1/份、不合并、不移除)。
    final inventory = ref.read(inventoryProvider);
    final proposals = IntakeProposalFactory.fromShoppingItems([item], inventory);
    ref.read(intakeReviewProvider.notifier).seed(proposals);

    final appliedIds = await Navigator.of(context).push<Set<String>>(
      fkRoute<Set<String>>(
        builder: (_) => const IntakeReviewScreen(title: '加入库存'),
      ),
    );

    // 只有当该项的入库提案(id 为 `ix_<itemId>`)真正被应用后,才从清单移除。
    if (!context.mounted) return;
    if (appliedIds == null || !appliedIds.contains('ix_${item.id}')) return;
    try {
      await ref.read(shoppingProvider.notifier).remove(item.id);
    } catch (_) {
      // 已入库但未能从清单清除,保留该项以便稍后重试移除。
    }
  }
}

class _ShoppingContentSliver extends StatelessWidget {
  const _ShoppingContentSliver({
    required this.visibleEntries,
    required this.selectedFilter,
    required this.collapsedCategories,
    required this.checkedCount,
    required this.onToggleCategory,
    required this.onItemToggle,
    required this.onItemDelete,
    required this.onClearChecked,
  });

  final List<MapEntry<String, List<ShoppingItem>>> visibleEntries;
  final ShoppingFilter selectedFilter;
  final Set<String> collapsedCategories;
  final int checkedCount;
  final ValueChanged<String> onToggleCategory;
  final ValueChanged<ShoppingItem> onItemToggle;
  final ValueChanged<ShoppingItem> onItemDelete;
  final VoidCallback onClearChecked;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(_buildItem, childCount: _itemCount),
    );
  }

  int get _itemCount =>
      visibleEntries.length +
      (visibleEntries.isEmpty ? 1 : 0) +
      (checkedCount > 0 ? 1 : 0);

  Widget _buildItem(BuildContext context, int index) {
    if (index < visibleEntries.length) {
      final entry = visibleEntries[index];
      return FkEntrance(
        index: index,
        child: _CategoryGroup(
          title: entry.key,
          items: entry.value,
          collapsed: collapsedCategories.contains(entry.key),
          onToggleCollapse: () => onToggleCategory(entry.key),
          onItemToggle: onItemToggle,
          onItemDelete: onItemDelete,
        ),
      );
    }

    if (visibleEntries.isEmpty && index == visibleEntries.length) {
      return _FilterEmptyMessage(filter: selectedFilter);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _ClearDoneButton(count: checkedCount, onTap: onClearChecked),
    );
  }
}

class _FilterEmptyMessage extends StatelessWidget {
  const _FilterEmptyMessage({required this.filter});

  final ShoppingFilter filter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.huge),
      child: Center(
        child: Text(
          filter == ShoppingFilter.todo ? '没有待购项目' : '没有已购项目',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
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
                        fontSize: AppFontSize.xs,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$done',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: AppFontSize.huge,
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
                  fontSize: AppFontSize.xxxl,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
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
  final ShoppingFilter selected;
  final int todoCount;
  final int doneCount;
  final void Function(ShoppingFilter) onSelect;
  const _FilterChipRow({
    required this.selected,
    required this.todoCount,
    required this.doneCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <(String, ShoppingFilter, int)>[
      ('全部', ShoppingFilter.all, todoCount + doneCount),
      ('待购买', ShoppingFilter.todo, todoCount),
      ('已购', ShoppingFilter.done, doneCount),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final (label, value, count) = chips[i];
          final active = value == selected;
          return GestureDetector(
            onTap: () => onSelect(value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: AppSpacing.sm,
              ),
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
                  fontSize: AppFontSize.sm,
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
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
                    const SizedBox(width: AppSpacing.sm),
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
                        fontSize: AppFontSize.xs,
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
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _ShopRow(
                          item: item,
                          isLast: index == items.length - 1,
                          onToggle: () => onItemToggle(item),
                          onDelete: () => onItemDelete(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShopRow extends StatelessWidget {
  static const _dividerDecoration = BoxDecoration(
    border: Border(bottom: BorderSide(color: AppColors.hair, width: 0.5)),
  );

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
        decoration: isLast ? null : _dividerDecoration,
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
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        decoration: checked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (item.detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.detail,
                        style: GoogleFonts.manrope(
                          fontSize: AppFontSize.xs,
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
                  padding: EdgeInsets.all(AppSpacing.xs),
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
      child: FkDashedBorder(
        radius: 12,
        color: AppColors.hair,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          alignment: Alignment.center,
          child: Text(
            '清空已完成 ($count)',
            style: GoogleFonts.manrope(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

