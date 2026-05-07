import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ingredient.dart';
import '../theme/app_theme.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../screens/ingredient_detail_screen.dart';
import '../widgets/inventory/ingredient_card.dart';
import '../widgets/common/category_chips.dart';
import '../widgets/common/swipe_reveal_delete_action.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  Future<void> _onRefresh() async {
    // Simulate a refresh; in a real app this would re-fetch from server
    await Future.delayed(const Duration(milliseconds: 800));
  }

  int _indexOfInventoryItem(Ingredient item) {
    return inventoryIndexOf(ref.read(inventoryProvider), item);
  }

  Future<void> _addToShoppingList(Ingredient item) async {
    final added = await ref
        .read(shoppingProvider.notifier)
        .addFromIngredient(item);
    if (!mounted) return;
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
        if (name != null) _showUpdatedSnackBar(name);
      case IngredientDetailResultType.deleted:
        final deletedItem = result.item;
        final index = result.index;
        if (deletedItem != null && index != null) {
          _showDeletedSnackBar(deletedItem, index);
        }
    }
  }

  void _showUpdatedSnackBar(String name) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「$name」已更新'),
        persist: false,
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _deleteItem(Ingredient item) {
    final index = _indexOfInventoryItem(item);
    if (index == -1) return;

    ref.read(inventoryProvider.notifier).remove(index);
    _showDeletedSnackBar(item, index);
  }

  void _showDeletedSnackBar(Ingredient item, int index) {
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
            ref.read(inventoryProvider.notifier).insertAt(index, item);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final filteredItems = ref.watch(filteredByCategoryProvider);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
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
                    Text(
                      '食材库存',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '管理您精心策划的新鲜食材收藏。',
                      style: GoogleFonts.manrope(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Category filters
            SliverToBoxAdapter(
              child: CategoryChips(
                categories: categories,
                leadingCategories: const [inventoryFilterNotFresh],
                selectedCategory: selectedCategory,
                onSelected: (category) {
                  ref.read(selectedCategoryProvider.notifier).state = category;
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            // Ingredient list
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver:
                  filteredItems.isEmpty
                      ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Text(
                              '该分类下暂无食材',
                              style: GoogleFonts.manrope(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      )
                      : SliverList.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return SwipeRevealDeleteAction(
                            key: ValueKey('inv_swipe_${item.name}_$index'),
                            deleteButtonKey: ValueKey(
                              'inventory_swipe_delete_${item.name}_$index',
                            ),
                            onDelete: () => _deleteItem(item),
                            child: IngredientCard(
                              ingredient: item,
                              onTap: () => _openItemDetail(item),
                              onBuyAgain: () => _addToShoppingList(item),
                            ),
                          );
                        },
                      ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}
