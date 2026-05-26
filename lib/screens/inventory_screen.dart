import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/food_categories.dart';
import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../screens/ingredient_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/dashboard/low_stock_card.dart';
import '../widgets/inventory/ingredient_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_top_bar.dart';

/// FreshKeeper 食材库 — 设计稿 `screens-2.jsx::IngredientsScreen`。
///
/// FK top bar + 搜索框 + 分类 chip 横滚(全部 / 5 大类)+ 状态 chip 横滚(全部 /
/// 不新鲜)+ 2-col grid IngredientCard。
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchCtrl = TextEditingController();

  // Multi-select state: stores indices into the currently-displayed `items` list.
  final Set<int> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _selectionMode => _selected.isNotEmpty;

  bool _canMerge(List<Ingredient> items) {
    if (_selected.length < 2) return false;
    final rows = _selected.map((i) => items[i]).toList();
    final first = rows.first;
    return rows.every(
      (r) =>
          r.name == first.name &&
          r.unit == first.unit &&
          r.storage == first.storage,
    );
  }

  Future<void> _mergeSelected(List<Ingredient> displayItems) async {
    final inventory = ref.read(inventoryProvider);
    // Map display indices → raw inventory indices
    final rawIndices =
        _selected
            .map(
              (displayIdx) =>
                  inventoryIndexOf(inventory, displayItems[displayIdx]),
            )
            .where((i) => i != -1)
            .toList()
          ..sort(
            (a, b) => b.compareTo(a),
          ); // descending so we remove from end first

    if (rawIndices.length < 2) {
      setState(() => _selected.clear());
      return;
    }

    final notifier = ref.read(inventoryProvider.notifier);
    // Merge all sources into the raw index that corresponds to the last selected display item.
    // Since rawIndices is sorted descending, the smallest raw index (last element) is the target.
    final target = rawIndices.last;
    for (final src in rawIndices.where((i) => i != target)) {
      await notifier.mergeBatch(src, target);
    }

    if (!mounted) return;
    setState(() => _selected.clear());
    showAppSnackBar(context, '已合并批次', backgroundColor: AppColors.primary);
  }

  Future<void> _onRefresh() async {
    try {
      ref.invalidate(inventoryProvider);
      ref.invalidate(filteredInventoryItemsProvider);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        '刷新食材失败，请稍后重试',
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _addToShoppingList(Ingredient item) async {
    final added = await ref
        .read(shoppingProvider.notifier)
        .addFromIngredient(item);
    if (!mounted) return;
    showAppSnackBar(
      context,
      added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
      backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    );
  }

  Future<void> _openItemDetail(Ingredient item) async {
    final result = await Navigator.of(context).push<IngredientDetailResult>(
      MaterialPageRoute(
        builder: (_) => IngredientDetailScreen(ingredient: item),
      ),
    );
    if (!mounted || result == null) return;
    switch (result.type) {
      case IngredientDetailResultType.updated:
        final name = result.name;
        if (name != null) {
          showAppSnackBar(
            context,
            '「$name」已更新',
            backgroundColor: AppColors.primary,
          );
        }
      case IngredientDetailResultType.deleted:
        final deletedItem = result.item;
        final index = result.index;
        if (deletedItem != null && index != null) {
          showAppSnackBar(
            context,
            '「${deletedItem.name}」已删除',
            backgroundColor: AppColors.error,
            actionLabel: '撤销',
            actionTextColor: AppColors.onError,
            onAction: () {
              ref.read(inventoryProvider.notifier).insertAt(index, deletedItem);
            },
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryCount = ref.watch(
      inventoryProvider.select((items) => items.length),
    );
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final query = ref.watch(inventorySearchQueryProvider);
    final items = ref.watch(filteredInventoryItemsProvider);
    final lowStock = ref.watch(lowStockItemsProvider);

    final canMerge = _canMerge(items);
    final showLowStockCta = lowStock.isNotEmpty && !_selectionMode;

    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_selectionMode) setState(() => _selected.clear());
          },
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child:
                        _selectionMode
                            ? _SelectionTopBar(
                              selectedCount: _selected.length,
                              canMerge: canMerge,
                              onCancel: () => setState(() => _selected.clear()),
                              onMerge: () => _mergeSelected(items),
                            )
                            : FkTopBar(
                              title: '我的食材',
                              subtitle: '共 $inventoryCount 件',
                              actions: [
                                FkIconButton(
                                  child: const Icon(Icons.tune_rounded),
                                  onTap: () {},
                                ),
                              ],
                            ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SearchField(
                    controller: _searchCtrl,
                    onChanged:
                        (v) =>
                            ref
                                .read(inventorySearchQueryProvider.notifier)
                                .state = v,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: _CategoryChipRow(
                    selected: selectedCategory,
                    onSelect:
                        (cat) =>
                            ref.read(selectedCategoryProvider.notifier).state =
                                cat,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          query.isNotEmpty ? '没有找到「$query」' : '该分类下暂无食材',
                          style: GoogleFonts.manrope(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.85,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = items[index];
                        final isSelected = _selected.contains(index);
                        return GestureDetector(
                          onLongPress: () {
                            setState(() => _selected.add(index));
                          },
                          onTap:
                              _selectionMode
                                  ? () {
                                    setState(() {
                                      if (isSelected) {
                                        _selected.remove(index);
                                      } else {
                                        _selected.add(index);
                                      }
                                    });
                                  }
                                  : () => _openItemDetail(item),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration:
                                isSelected
                                    ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 2.5,
                                      ),
                                    )
                                    : null,
                            child: IngredientCard(
                              key: ValueKey('inv_${item.name}_$index'),
                              ingredient: item,
                              onTap: null,
                              onBuyAgain:
                                  _selectionMode
                                      ? null
                                      : () => _addToShoppingList(item),
                            ),
                          ),
                        );
                      }, childCount: items.length),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (showLowStockCta)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                key: const Key('inventory_low_stock_cta'),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text('补货 ${lowStock.length} 项'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => runBulkLowStockAdd(context, ref, lowStock),
              ),
            ),
          ),
      ],
    );
  }
}

/// Top bar shown when in multi-select mode.
class _SelectionTopBar extends StatelessWidget {
  final int selectedCount;
  final bool canMerge;
  final VoidCallback onCancel;
  final VoidCallback onMerge;

  const _SelectionTopBar({
    required this.selectedCount,
    required this.canMerge,
    required this.onCancel,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.close_rounded,
              size: 22,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '已选 $selectedCount 件',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
          if (canMerge)
            GestureDetector(
              onTap: onMerge,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '合并 $selectedCount 批',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurface,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  hintText: '搜索食材',
                  hintStyle: GoogleFonts.manrope(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _categoryChipSignature(List<Ingredient> inventory) {
  final counts = <String, int>{};
  for (final item in inventory) {
    final cat = FoodCategories.dropdownValue(item.category);
    counts[cat] = (counts[cat] ?? 0) + 1;
  }
  final entries =
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final notFresh = notFreshIngredientCount(inventory);
  return [
    'total:${inventory.length}',
    'notFresh:$notFresh',
    ...entries.map((entry) => '${entry.key}:${entry.value}'),
  ].join('|');
}

class _CategoryChipRow extends ConsumerWidget {
  final String selected;
  final void Function(String) onSelect;
  const _CategoryChipRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(inventoryProvider.select(_categoryChipSignature));
    final inventory = ref.read(inventoryProvider);
    final categoryCounts = <String, int>{};
    for (final item in inventory) {
      final cat = FoodCategories.dropdownValue(item.category);
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    final chips = <_Chip>[
      _Chip(label: '全部', value: inventoryFilterAll, count: inventory.length),
      _Chip(
        label: '不新鲜',
        value: inventoryFilterNotFresh,
        count:
            inventory
                .where(
                  (i) =>
                      i.state == FreshnessState.expiringSoon ||
                      i.state == FreshnessState.expired,
                )
                .length,
      ),
      ...FoodCategories.values.map(
        (cat) => _Chip(label: cat, value: cat, count: categoryCounts[cat] ?? 0),
      ),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = chips[i];
          final active = c.value == selected;
          return GestureDetector(
            onTap: () => onSelect(c.value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.hair,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                c.count > 0 ? '${c.label} · ${c.count}' : c.label,
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

class _Chip {
  final String label;
  final String value;
  final int count;
  _Chip({required this.label, required this.value, required this.count});
}
