import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/food_details.dart';
import '../../models/ingredient.dart';
import '../../models/shopping_item.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../screens/ingredient_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/page_transitions.dart';
import '../../utils/storage_labels.dart';
import '../shared/category_icon.dart';
import '../shared/fk_entrance.dart';
import '../shared/recipe_image.dart';

const _searchDebounceDuration = Duration(milliseconds: 150);
const _maxVisibleResultsPerSection = 5;

class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _queueSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      ref.read(searchProvider.notifier).state = value;
    });
  }

  void _setSearchNow(String value) {
    _debounce?.cancel();
    ref.read(searchProvider.notifier).state = value;
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    final term = _controller.text.trim();
    if (term.isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(term);
    }
    _controller.clear();
    _setSearchNow('');
    ref.read(searchActiveProvider.notifier).state = false;
  }

  void _selectHistoryTerm(String term) {
    _controller.text = term;
    _setSearchNow(term);
  }

  void _openInventoryResult() {
    ref.read(selectedCategoryProvider.notifier).state = inventoryFilterAll;
    ref.navigateToTab(FkTab.fridge);
    _close();
  }

  void _openShoppingResult(ShoppingItem item) {
    ref.read(collapsedShoppingCategoriesProvider.notifier).update((collapsed) {
      final next = {...collapsed}..remove(item.category);
      return next;
    });
    ref.navigateToTab(FkTab.shopping);
    _close();
  }

  void _openFoodDetails(FoodDetails details) {
    final navigator = Navigator.of(context);
    final ingredient = _ingredientForDetails(details);
    _close();
    navigator.push(
      fkRoute<void>(
        builder: (_) => IngredientDetailScreen(ingredient: ingredient),
      ),
    );
  }

  Ingredient _ingredientForDetails(FoodDetails details) {
    final keyword = _controller.text.trim();
    final name = keyword.isNotEmpty ? keyword : details.displayName;
    return Ingredient(
      name: name,
      quantity: '1',
      unit: '份',
      imageUrl: details.imageUrl ?? '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: details.category,
      storage: details.storage,
      shelfLifeDays: details.shelfLifeDays,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _close,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: AppColors.onSurface.withValues(alpha: 0.4)),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SearchField(
                  controller: _controller,
                  onChanged: _queueSearch,
                  onSubmitted: (value) {
                    final term = value.trim();
                    if (term.isNotEmpty) {
                      ref.read(searchHistoryProvider.notifier).add(term);
                    }
                    _setSearchNow(value);
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                  onClose: _close,
                ),
                _SearchContent(
                  onHistorySelected: _selectHistoryTerm,
                  onInventorySelected: _openInventoryResult,
                  onShoppingSelected: _openShoppingResult,
                  onFoodDetailsSelected: _openFoodDetails,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: '搜索食材...',
          hintStyle: const TextStyle(color: AppColors.outline),
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, color: AppColors.outline),
            onPressed: onClose,
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SearchContent extends ConsumerWidget {
  const _SearchContent({
    required this.onHistorySelected,
    required this.onInventorySelected,
    required this.onShoppingSelected,
    required this.onFoodDetailsSelected,
  });

  final ValueChanged<String> onHistorySelected;
  final VoidCallback onInventorySelected;
  final ValueChanged<ShoppingItem> onShoppingSelected;
  final ValueChanged<FoodDetails> onFoodDetailsSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyword = ref.watch(trimmedSearchKeywordProvider);
    if (keyword.isEmpty) {
      return Flexible(
        child: _SearchHistoryPanel(onSelected: onHistorySelected),
      );
    }

    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: _SearchResultsPanel(
          onInventorySelected: onInventorySelected,
          onShoppingSelected: onShoppingSelected,
          onFoodDetailsSelected: onFoodDetailsSelected,
        ),
      ),
    );
  }
}

class _SearchHistoryPanel extends ConsumerWidget {
  const _SearchHistoryPanel({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '最近搜索',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.primary,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(searchHistoryProvider.notifier).clear(),
                        child: Text(
                          '清除',
                          style: GoogleFonts.manrope(
                            fontSize: AppFontSize.sm,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final term = history[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.history,
                          size: 18,
                          color: AppColors.outline,
                        ),
                        title: Text(
                          term,
                          style: GoogleFonts.manrope(
                            fontSize: AppFontSize.md,
                            color: AppColors.onSurface,
                          ),
                        ),
                        trailing: GestureDetector(
                          onTap: () => ref
                              .read(searchHistoryProvider.notifier)
                              .remove(term),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.outline,
                          ),
                        ),
                        onTap: () => onSelected(term),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultsPanel extends ConsumerWidget {
  const _SearchResultsPanel({
    required this.onInventorySelected,
    required this.onShoppingSelected,
    required this.onFoodDetailsSelected,
  });

  final VoidCallback onInventorySelected;
  final ValueChanged<ShoppingItem> onShoppingSelected;
  final ValueChanged<FoodDetails> onFoodDetailsSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryResults = ref.watch(filteredInventoryProvider);
    final shoppingResults = ref.watch(filteredShoppingProvider);
    final foodDetailsResult = ref.watch(searchFoodDetailsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: _SearchResultsList(
            inventory: inventoryResults,
            shopping: shoppingResults,
            foodDetailsResult: foodDetailsResult,
            onInventorySelected: onInventorySelected,
            onShoppingSelected: onShoppingSelected,
            onFoodDetailsSelected: onFoodDetailsSelected,
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.inventory,
    required this.shopping,
    required this.foodDetailsResult,
    required this.onInventorySelected,
    required this.onShoppingSelected,
    required this.onFoodDetailsSelected,
  });

  final List<Ingredient> inventory;
  final List<ShoppingItem> shopping;
  final AsyncValue<FoodDetails?> foodDetailsResult;
  final VoidCallback onInventorySelected;
  final ValueChanged<ShoppingItem> onShoppingSelected;
  final ValueChanged<FoodDetails> onFoodDetailsSelected;

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) {
      return FkEntrance(child: _EmptySearchResults());
    }

    // Track a separate counter for content rows (inventory / shopping /
    // foodDetails) so stagger indices stay compact and meaningful.
    var contentIndex = 0;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: rows.length,
      itemExtentBuilder: (index, dimensions) => rows[index].extent,
      itemBuilder: (context, index) {
        final row = rows[index];
        final isContent =
            row.kind == _SearchResultRowKind.inventory ||
            row.kind == _SearchResultRowKind.shopping ||
            row.kind == _SearchResultRowKind.foodDetails;
        final widget = _buildRow(row);
        if (isContent) {
          final i = contentIndex++;
          return FkEntrance(index: i, child: widget);
        }
        return widget;
      },
    );
  }

  List<_SearchResultRow> _rows() {
    final rows = <_SearchResultRow>[];
    if (inventory.isNotEmpty) {
      rows.add(
        _SearchResultRow.header(
          title: '库存食材',
          icon: Icons.kitchen_outlined,
          count: inventory.length,
        ),
      );
      rows.addAll(
        inventory
            .take(_maxVisibleResultsPerSection)
            .map(_SearchResultRow.inventory),
      );
      final remaining = inventory.length - _maxVisibleResultsPerSection;
      if (remaining > 0) {
        rows.add(_SearchResultRow.hint(remaining: remaining, section: '库存'));
      }
    }

    if (inventory.isNotEmpty && shopping.isNotEmpty) {
      rows.add(const _SearchResultRow.divider());
    }

    if (shopping.isNotEmpty) {
      rows.add(
        _SearchResultRow.header(
          title: '购物清单',
          icon: Icons.shopping_cart_outlined,
          count: shopping.length,
        ),
      );
      rows.addAll(
        shopping
            .take(_maxVisibleResultsPerSection)
            .map(_SearchResultRow.shopping),
      );
      final remaining = shopping.length - _maxVisibleResultsPerSection;
      if (remaining > 0) {
        rows.add(_SearchResultRow.hint(remaining: remaining, section: '购物清单'));
      }
    }

    final details = foodDetailsResult.asData?.value;
    final hasDetailsState =
        foodDetailsResult.isLoading ||
        details != null ||
        foodDetailsResult.hasError;
    if ((inventory.isNotEmpty || shopping.isNotEmpty) && hasDetailsState) {
      rows.add(const _SearchResultRow.divider());
    }
    if (foodDetailsResult.isLoading) {
      rows.add(
        const _SearchResultRow.header(
          title: '食材百科',
          icon: Icons.info_outline,
          count: 1,
        ),
      );
      rows.add(const _SearchResultRow.loading());
    } else if (details != null) {
      rows.add(
        const _SearchResultRow.header(
          title: '食材百科',
          icon: Icons.info_outline,
          count: 1,
        ),
      );
      rows.add(_SearchResultRow.foodDetails(details));
    } else if (foodDetailsResult.hasError) {
      rows.add(
        const _SearchResultRow.header(
          title: '食材百科',
          icon: Icons.info_outline,
          count: 1,
        ),
      );
      rows.add(const _SearchResultRow.error());
    }

    return rows;
  }

  Widget _buildRow(_SearchResultRow row) {
    return switch (row.kind) {
      _SearchResultRowKind.header => _SectionHeader(
        title: row.title!,
        icon: row.icon!,
        count: row.count!,
      ),
      _SearchResultRowKind.divider => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
      ),
      _SearchResultRowKind.inventory => _InventoryResultTile(
        item: row.inventory!,
        onTap: onInventorySelected,
      ),
      _SearchResultRowKind.shopping => _ShoppingResultTile(
        item: row.shopping!,
        onTap: () => onShoppingSelected(row.shopping!),
      ),
      _SearchResultRowKind.foodDetails => _FoodDetailsResultTile(
        details: row.foodDetails!,
        onTap: () => onFoodDetailsSelected(row.foodDetails!),
      ),
      _SearchResultRowKind.loading => const _FoodDetailsLoadingTile(),
      _SearchResultRowKind.error => const _FoodDetailsErrorTile(),
      _SearchResultRowKind.hint => _ShowMoreHint(
        remaining: row.remaining!,
        section: row.section!,
      ),
    };
  }
}

enum _SearchResultRowKind {
  header,
  divider,
  inventory,
  shopping,
  foodDetails,
  loading,
  error,
  hint,
}

class _SearchResultRow {
  const _SearchResultRow._({
    required this.kind,
    required this.extent,
    this.title,
    this.icon,
    this.count,
    this.inventory,
    this.shopping,
    this.foodDetails,
    this.remaining,
    this.section,
  });

  const _SearchResultRow.header({
    required String title,
    required IconData icon,
    required int count,
  }) : this._(
         kind: _SearchResultRowKind.header,
         extent: 44,
         title: title,
         icon: icon,
         count: count,
       );

  const _SearchResultRow.divider()
    : this._(kind: _SearchResultRowKind.divider, extent: 1);

  _SearchResultRow.inventory(Ingredient item)
    : this._(kind: _SearchResultRowKind.inventory, extent: 64, inventory: item);

  _SearchResultRow.shopping(ShoppingItem item)
    : this._(kind: _SearchResultRowKind.shopping, extent: 64, shopping: item);

  _SearchResultRow.foodDetails(FoodDetails details)
    : this._(
        kind: _SearchResultRowKind.foodDetails,
        extent: 72,
        foodDetails: details,
      );

  const _SearchResultRow.loading()
    : this._(kind: _SearchResultRowKind.loading, extent: 56);

  const _SearchResultRow.error()
    : this._(kind: _SearchResultRowKind.error, extent: 64);

  const _SearchResultRow.hint({required int remaining, required String section})
    : this._(
        kind: _SearchResultRowKind.hint,
        extent: 40,
        remaining: remaining,
        section: section,
      );

  final _SearchResultRowKind kind;
  final double extent;
  final String? title;
  final IconData? icon;
  final int? count;
  final Ingredient? inventory;
  final ShoppingItem? shopping;
  final FoodDetails? foodDetails;
  final int? remaining;
  final String? section;
}

class _EmptySearchResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.huge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 40,
            color: AppColors.outline,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '未找到匹配的结果',
            style: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant,
              fontSize: AppFontSize.md,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  final String title;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryResultTile extends StatelessWidget {
  const _InventoryResultTile({required this.item, required this.onTap});

  final Ingredient item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (item.state) {
      FreshnessState.fresh => AppColors.primary,
      FreshnessState.expiringSoon => AppColors.secondary,
      FreshnessState.urgent => AppColors.error,
      FreshnessState.expired => AppColors.error,
    };

    return ListTile(
      dense: true,
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
      ),
      title: Text(
        item.name,
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: Text(
        '${item.quantity} ${item.unit}${item.category != null ? ' · ${item.category}' : ''}',
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.sm,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      trailing: item.expiryLabel != null
          ? Text(
              item.expiryLabel!,
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.xs,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _ShoppingResultTile extends StatelessWidget {
  const _ShoppingResultTile({required this.item, required this.onTap});

  final ShoppingItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        item.isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 20,
        color: item.isChecked ? AppColors.primary : AppColors.outline,
      ),
      title: Text(
        item.name,
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: item.isChecked
              ? AppColors.onSurfaceVariant
              : AppColors.onSurface,
          decoration: item.isChecked ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${item.detail} · ${item.category}',
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.sm,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FoodDetailsResultTile extends StatelessWidget {
  const _FoodDetailsResultTile({required this.details, required this.onTap});

  final FoodDetails details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 44,
          height: 44,
          child: RecipeImage(
            imageSource: details.imageUrl,
            fit: BoxFit.cover,
            semanticLabel: details.displayName,
            fallback: CategoryIconAvatar(
              category: details.category,
              size: 44,
              iconSize: 20,
              borderRadius: 10,
            ),
          ),
        ),
      ),
      title: Text(
        details.displayName,
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: Text(
        _foodDetailsSummary(details),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.sm,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FoodDetailsLoadingTile extends StatelessWidget {
  const _FoodDetailsLoadingTile();

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      dense: true,
      leading: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      title: Text('正在查询联网食材信息...'),
    );
  }
}

class _FoodDetailsErrorTile extends StatelessWidget {
  const _FoodDetailsErrorTile();

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      dense: true,
      leading: Icon(Icons.error_outline, color: AppColors.error),
      title: Text('食材百科查询失败'),
      subtitle: Text('请稍后重试'),
    );
  }
}

class _ShowMoreHint extends StatelessWidget {
  const _ShowMoreHint({required this.remaining, required this.section});

  final int remaining;
  final String section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        '还有 $remaining 个$section结果...',
        style: GoogleFonts.manrope(
          fontSize: AppFontSize.sm,
          color: AppColors.outline,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

String _foodDetailsSummary(FoodDetails details) {
  final parts = <String>[];
  final description = details.description.trim();
  if (_isUsefulFoodDetailsDescription(description)) {
    parts.add(description);
  }

  final category = details.category.trim();
  if (category.isNotEmpty) {
    parts.add(category);
  }

  parts.add('${storageLabelFor(details.storage)}保存');

  final shelfLifeDays = details.shelfLifeDays;
  if (shelfLifeDays != null && shelfLifeDays > 0) {
    parts.add('约 $shelfLifeDays 天');
  }

  return parts.isEmpty ? '查看食材详情' : parts.join(' · ');
}

bool _isUsefulFoodDetailsDescription(String description) {
  if (description.isEmpty) return false;
  if (description.startsWith('Open Food Facts 记录的') &&
      description.endsWith('食品。')) {
    return false;
  }
  if (description.startsWith('建议存放在')) return false;
  if (description.startsWith('暂无联网详情')) return false;
  return true;
}
