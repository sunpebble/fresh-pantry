import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../providers/food_details_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_pill.dart';
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

/// 食材详情 — 设计稿 `screens-2.jsx::DetailScreen`。
///
/// 视觉:
/// - Hero block 背景用 cat.tint,叠加 4 处散落 ghost CatIcon、2 个 soft blob、
///   subtle dot grid。中央是 92×92 软玻璃 avatar + CatIcon。
/// - 主体:数量/天数 split card → 食材信息 list → 操作行(加购 / 编辑 / 删除)。
class IngredientDetailScreen extends ConsumerStatefulWidget {
  const IngredientDetailScreen({super.key, required this.ingredient});

  final Ingredient ingredient;

  @override
  ConsumerState<IngredientDetailScreen> createState() =>
      _IngredientDetailScreenState();
}

class _IngredientDetailScreenState
    extends ConsumerState<IngredientDetailScreen> {
  Future<void> _addToShoppingList(Ingredient item) async {
    final bool added;
    try {
      added = await ref
          .read(shoppingProvider.notifier)
          .addFromIngredient(item);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '加入购物清单失败，请重试');
      return;
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
      backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    );
  }

  Future<void> _editItem(Ingredient item) async {
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
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
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
    if (index == -1) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除食材',
      content: '确定要删除「${item.name}」吗？此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!mounted || !confirmed) return;

    try {
      await ref.read(inventoryProvider.notifier).remove(index);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '删除失败，请重试');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(IngredientDetailResult.deleted(item, index));
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      inventoryProvider.select((items) {
        final index = inventoryIndexOf(items, widget.ingredient);
        return (
          index: index,
          item: index == -1 ? widget.ingredient : items[index],
        );
      }),
    );
    final item = current.item;
    final index = current.index;
    final isInventoryItem = index != -1;
    final detailsAsync = ref.watch(foodDetailsProvider(item));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: detailsAsync.when(
        data: (details) => _buildBody(item, details, isInventoryItem),
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        error:
            (_, _) =>
                _buildBody(item, fallbackFoodDetailsFor(item), isInventoryItem),
      ),
    );
  }

  Widget _buildBody(
    Ingredient item,
    FoodDetails details,
    bool isInventoryItem,
  ) {
    final catId = fkCategoryIdFor(item.category);
    final palette = FkCategoryPalette.of(catId);
    final statusBadge = _statusBadgeFor(item.state);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DetailHero(
                  catId: catId,
                  palette: palette,
                  itemName: details.displayName,
                  categoryName: details.category,
                  zoneLabel: storageLabelFor(item.storage),
                  statusBadge: statusBadge,
                  onBack: () => Navigator.of(context).maybePop(),
                  onEdit: isInventoryItem ? () => _editItem(item) : null,
                  onDelete: isInventoryItem ? () => _confirmDelete(item) : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _QtyAndFreshnessCard(
                        quantity: item.quantity,
                        unit: item.unit,
                        freshnessPercent: item.freshnessPercent,
                        expiryLabel: item.expiryLabel,
                        state: item.state,
                      ),
                      if (details.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        FkCard(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            details.description,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              height: 1.6,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _InfoList(item: item, details: details),
                      const SizedBox(height: 14),
                      _ActionRow(
                        onAddToShopping: () => _addToShoppingList(item),
                        showInventoryActions: isInventoryItem,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _statusBadgeFor(FreshnessState state) {
    return switch (state) {
      FreshnessState.fresh => null,
      FreshnessState.expiringSoon => FkPill.status(FkStatus.soon),
      FreshnessState.urgent => FkPill.status(FkStatus.urgent),
      FreshnessState.expired => FkPill.status(FkStatus.expired),
    };
  }
}

class _DetailHero extends StatelessWidget {
  final String catId;
  final FkCatColors palette;
  final String itemName;
  final String categoryName;
  final String zoneLabel;
  final Widget? statusBadge;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _DetailHero({
    required this.catId,
    required this.palette,
    required this.itemName,
    required this.categoryName,
    required this.zoneLabel,
    required this.statusBadge,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(AppRadius.hero),
        bottomRight: Radius.circular(AppRadius.hero),
      ),
      child: Container(
        color: palette.tint,
        child: Stack(
          children: [
            // Scattered ghost icons
            Positioned(
              top: 64,
              right: -8,
              child: Opacity(
                opacity: 0.18,
                child: Transform.rotate(
                  angle: 0.31,
                  child: CatIcon(category: catId, size: 90, color: palette.ink),
                ),
              ),
            ),
            Positioned(
              top: 150,
              right: 80,
              child: Opacity(
                opacity: 0.18,
                child: Transform.rotate(
                  angle: -0.21,
                  child: CatIcon(category: catId, size: 42, color: palette.ink),
                ),
              ),
            ),
            Positioned(
              bottom: 14,
              right: 24,
              child: Opacity(
                opacity: 0.18,
                child: Transform.rotate(
                  angle: 0.14,
                  child: CatIcon(category: catId, size: 56, color: palette.ink),
                ),
              ),
            ),
            Positioned(
              top: 100,
              left: 60,
              child: Opacity(
                opacity: 0.18,
                child: Transform.rotate(
                  angle: -0.38,
                  child: CatIcon(category: catId, size: 28, color: palette.ink),
                ),
              ),
            ),
            // Soft blobs
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              left: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Row(
                    children: [
                      FkIconButton(
                        onTap: onBack,
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                        ),
                      ),
                      const Spacer(),
                      if (onEdit != null)
                        FkIconButton(
                          onTap: onEdit!,
                          child: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 8),
                        FkIconButton(
                          onTap: onDelete!,
                          foregroundColor: AppColors.fkDanger,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadowSoft,
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: CatIcon(
                            category: catId,
                            size: 64,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              itemName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (statusBadge != null) ...[
                            const SizedBox(width: 10),
                            statusBadge!,
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$categoryName · $zoneLabel',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyAndFreshnessCard extends StatelessWidget {
  final String quantity;
  final String unit;
  final double freshnessPercent;
  final String? expiryLabel;
  final FreshnessState state;

  const _QtyAndFreshnessCard({
    required this.quantity,
    required this.unit,
    required this.freshnessPercent,
    required this.expiryLabel,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (freshnessPercent.clamp(0.0, 1.0) * 100).round();
    final percentColor = switch (state) {
      FreshnessState.fresh => AppColors.primary,
      FreshnessState.expiringSoon => AppColors.fkWarn,
      FreshnessState.urgent => AppColors.fkDanger,
      FreshnessState.expired => AppColors.fkDanger,
    };
    return FkCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.hair, width: 0.5),
                  ),
                ),
                child: _StatColumn(
                  label: '当前数量',
                  value: quantity,
                  unit: unit,
                  valueColor: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _StatColumn(
                  label: '新鲜度',
                  value: '$percent',
                  unit: '%',
                  hint: expiryLabel,
                  valueColor: percentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String? hint;
  final Color valueColor;
  const _StatColumn({
    required this.label,
    required this.value,
    required this.unit,
    this.hint,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.heroSubStat.copyWith(color: valueColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoList extends StatelessWidget {
  final Ingredient item;
  final FoodDetails details;
  const _InfoList({required this.item, required this.details});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('分类', details.category),
      ('存放位置', storageLabelFor(item.storage)),
      if (details.shelfLifeDays != null) ('保质期建议', '${details.shelfLifeDays}天'),
      ('来源', details.source),
    ];
    return FkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                border:
                    i == rows.length - 1
                        ? null
                        : const Border(
                          bottom: BorderSide(color: AppColors.hair, width: 0.5),
                        ),
              ),
              child: Row(
                children: [
                  Text(
                    rows[i].$1,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onAddToShopping;
  final bool showInventoryActions;
  const _ActionRow({
    required this.onAddToShopping,
    required this.showInventoryActions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onAddToShopping,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: AppColors.primaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '加入清单',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
