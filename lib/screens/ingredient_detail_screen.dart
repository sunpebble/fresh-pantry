import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../providers/food_details_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/recipe_image.dart';
import 'add_ingredient_screen.dart';

enum IngredientDetailResultType { updated, deleted }

class IngredientDetailResult {
  const IngredientDetailResult._({
    required this.type,
    this.name,
    this.item,
    this.index,
  });

  final IngredientDetailResultType type;
  final String? name;
  final Ingredient? item;
  final int? index;

  factory IngredientDetailResult.updated(String name) {
    return IngredientDetailResult._(
      type: IngredientDetailResultType.updated,
      name: name,
    );
  }

  factory IngredientDetailResult.deleted(Ingredient item, int index) {
    return IngredientDetailResult._(
      type: IngredientDetailResultType.deleted,
      item: item,
      index: index,
    );
  }
}

class IngredientDetailScreen extends ConsumerStatefulWidget {
  const IngredientDetailScreen({super.key, required this.ingredient});

  final Ingredient ingredient;

  @override
  ConsumerState<IngredientDetailScreen> createState() =>
      _IngredientDetailScreenState();
}

class _IngredientDetailScreenState
    extends ConsumerState<IngredientDetailScreen> {
  int _indexOf(Ingredient item) {
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

  Future<void> _editItem(Ingredient item) async {
    final index = _indexOf(item);
    if (index == -1) return;

    final updatedName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              backgroundColor: AppColors.surface,
              body: SafeArea(
                child: AddIngredientScreen(
                  initialIngredient: item,
                  inventoryIndex: index,
                ),
              ),
            ),
      ),
    );
    if (!mounted || updatedName == null) return;
    Navigator.of(context).pop(IngredientDetailResult.updated(updatedName));
  }

  Future<void> _confirmDelete(Ingredient item) async {
    final index = _indexOf(item);
    if (index == -1) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '删除食材',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              '确定要删除「${item.name}」吗？此操作不可撤销。',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  '取消',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  '删除',
                  style: GoogleFonts.manrope(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) return;

    ref.read(inventoryProvider.notifier).remove(index);
    Navigator.of(context).pop(IngredientDetailResult.deleted(item, index));
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final index = inventoryIndexOf(inventory, widget.ingredient);
    final item = index == -1 ? widget.ingredient : inventory[index];
    final isInventoryItem = index != -1;
    final detailsAsync = ref.watch(foodDetailsProvider(item));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('食材详情'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
      ),
      body: detailsAsync.when(
        data: (details) => _buildDetails(item, details),
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        error: (_, _) => _buildDetails(item, fallbackFoodDetailsFor(item)),
      ),
      bottomNavigationBar: _ActionBar(
        onAddToShopping: () => _addToShoppingList(item),
        onEdit: () => _editItem(item),
        onDelete: () => _confirmDelete(item),
        showInventoryActions: isInventoryItem,
      ),
    );
  }

  Widget _buildDetails(Ingredient item, FoodDetails details) {
    final imageSource =
        details.imageUrl?.trim().isNotEmpty == true
            ? details.imageUrl
            : item.imageUrl.trim().isNotEmpty
            ? item.imageUrl
            : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 220,
            width: double.infinity,
            color: AppColors.surfaceContainerLow,
            child: RecipeImage(
              imageSource: imageSource,
              fit: BoxFit.cover,
              fallback: Center(
                child: CategoryIconAvatar(
                  category: details.category,
                  size: 120,
                  iconSize: 52,
                  borderRadius: 20,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          details.displayName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          details.description,
          style: GoogleFonts.manrope(
            fontSize: 15,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InfoChip(label: '分类：${details.category}'),
            _InfoChip(label: '建议存放：${storageLabelFor(details.storage)}'),
            if (details.shelfLifeDays != null)
              _InfoChip(label: '保质期建议：${details.shelfLifeDays}天'),
            _InfoChip(label: '来源：${details.source}'),
          ],
        ),
      ],
    );
  }

}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onAddToShopping,
    required this.onEdit,
    required this.onDelete,
    required this.showInventoryActions,
  });

  final VoidCallback onAddToShopping;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool showInventoryActions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final addButton = FilledButton.icon(
              onPressed: onAddToShopping,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('加入购物清单'),
            );

            if (!showInventoryActions) {
              return SizedBox(width: double.infinity, child: addButton);
            }

            final secondaryActions = Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const _ActionLabel('编辑'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const _ActionLabel('删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 360) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: addButton),
                  const SizedBox(height: 8),
                  secondaryActions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: addButton),
                const SizedBox(width: 8),
                SizedBox(width: 184, child: secondaryActions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
