import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/food_details.dart';
import '../../models/ingredient.dart';
import '../../models/shopping_item.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/search_provider.dart';
import '../../screens/ingredient_detail_screen.dart';
import '../../utils/storage_labels.dart';
import '../shared/category_icon.dart';
import '../shared/recipe_image.dart';

class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    final term = _controller.text.trim();
    if (term.isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(term);
    }
    _controller.clear();
    ref.read(searchProvider.notifier).state = '';
    ref.read(searchActiveProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(searchActiveProvider);
    if (!isActive) return const SizedBox.shrink();

    final keyword = ref.watch(searchProvider).trim();
    final inventoryResults = ref.watch(filteredInventoryProvider);
    final shoppingResults = ref.watch(filteredShoppingProvider);
    final foodDetailsResult =
        keyword.isNotEmpty ? ref.watch(searchFoodDetailsProvider) : null;
    final hasQuery = keyword.isNotEmpty;

    return Stack(
      children: [
        // Blurred background tap-to-dismiss
        GestureDetector(
          onTap: _close,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: AppColors.onSurface.withValues(alpha: 0.4)),
          ),
        ),
        // Search panel
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search field
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
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
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      ref.read(searchProvider.notifier).state = value;
                    },
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        ref.read(searchHistoryProvider.notifier).add(value);
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    decoration: InputDecoration(
                      hintText: '搜索食材...',
                      hintStyle: TextStyle(color: AppColors.outline),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.primary,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, color: AppColors.outline),
                        onPressed: _close,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Results
                if (hasQuery) ...[
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.55,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
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
                        borderRadius: BorderRadius.circular(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildResultsList(
                            inventoryResults,
                            shoppingResults,
                            foodDetailsResult,
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  _buildSearchHistory(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHistory() {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '最近搜索',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.primary,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(searchHistoryProvider.notifier).clear();
                      },
                      child: Text(
                        '清除',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...history.map(
                (term) => ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.history,
                    size: 18,
                    color: AppColors.outline,
                  ),
                  title: Text(
                    term,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurface,
                    ),
                  ),
                  trailing: GestureDetector(
                    onTap: () {
                      ref.read(searchHistoryProvider.notifier).remove(term);
                    },
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.outline,
                    ),
                  ),
                  onTap: () {
                    _controller.text = term;
                    ref.read(searchProvider.notifier).state = term;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(
    List<Ingredient> inventory,
    List<ShoppingItem> shopping,
    AsyncValue<FoodDetails?>? foodDetailsResult,
  ) {
    final hasInventory = inventory.isNotEmpty;
    final hasShopping = shopping.isNotEmpty;
    final foodDetails = foodDetailsResult?.maybeWhen(
      data: (details) => details,
      orElse: () => null,
    );
    final hasFoodDetails = foodDetails != null;
    final isLoadingFoodDetails = foodDetailsResult?.isLoading ?? false;

    if (!hasInventory &&
        !hasShopping &&
        !hasFoodDetails &&
        !isLoadingFoodDetails) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: AppColors.outline),
            const SizedBox(height: 12),
            Text(
              '未找到匹配的结果',
              style: GoogleFonts.manrope(
                color: AppColors.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Inventory results
        if (hasInventory) ...[
          _buildSectionHeader('库存食材', Icons.kitchen_outlined, inventory.length),
          ...inventory.take(5).map(_buildInventoryTile),
          if (inventory.length > 5)
            _buildShowMoreHint(inventory.length - 5, '库存'),
        ],

        // Divider between sections
        if (hasInventory && hasShopping)
          const Divider(height: 1, indent: 16, endIndent: 16),

        // Shopping results
        if (hasShopping) ...[
          _buildSectionHeader(
            '购物清单',
            Icons.shopping_cart_outlined,
            shopping.length,
          ),
          ...shopping.take(5).map(_buildShoppingTile),
          if (shopping.length > 5)
            _buildShowMoreHint(shopping.length - 5, '购物清单'),
        ],

        if ((hasInventory || hasShopping) &&
            (hasFoodDetails || isLoadingFoodDetails))
          const Divider(height: 1, indent: 16, endIndent: 16),

        if (isLoadingFoodDetails) ...[
          _buildSectionHeader('食材百科', Icons.info_outline, 1),
          const ListTile(
            dense: true,
            leading: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('正在查询联网食材信息...'),
          ),
        ] else if (hasFoodDetails) ...[
          _buildSectionHeader('食材百科', Icons.info_outline, 1),
          _buildFoodDetailsTile(foodDetails),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTile(Ingredient item) {
    final Color statusColor = switch (item.state) {
      FreshnessState.fresh => AppColors.primary,
      FreshnessState.expiringSoon => AppColors.secondary,
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: Text(
        '${item.quantity} ${item.unit}${item.category != null ? ' · ${item.category}' : ''}',
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      trailing:
          item.expiryLabel != null
              ? Text(
                item.expiryLabel!,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              )
              : null,
      onTap: () {
        // Navigate to inventory tab and close search
        ref.read(selectedCategoryProvider.notifier).state = inventoryFilterAll;
        ref.navigateToTab(1);
        _close();
      },
    );
  }

  Widget _buildShoppingTile(ShoppingItem item) {
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color:
              item.isChecked ? AppColors.onSurfaceVariant : AppColors.onSurface,
          decoration: item.isChecked ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${item.detail} · ${item.category}',
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      onTap: () {
        // Navigate to shopping list tab and close search
        ref.read(shoppingCategoryToExpandProvider.notifier).state =
            item.category;
        ref.navigateToTab(3);
        _close();
      },
    );
  }

  Widget _buildFoodDetailsTile(FoodDetails details) {
    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: Text(
        _foodDetailsSummary(details),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      onTap: () => _openFoodDetails(details),
    );
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

  void _openFoodDetails(FoodDetails details) {
    final navigator = Navigator.of(context);
    final ingredient = _ingredientForDetails(details);
    _close();
    navigator.push(
      MaterialPageRoute(
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

  Widget _buildShowMoreHint(int remaining, String section) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '还有 $remaining 个$section结果...',
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: AppColors.outline,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
