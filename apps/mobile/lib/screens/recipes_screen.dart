import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../utils/safe_push.dart';
import '../widgets/recipe_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_skeleton_card.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'custom_recipe_detail_screen.dart';
import 'custom_recipe_form_screen.dart';
import 'recipe_detail_screen.dart';

/// FreshKeeper 菜谱 tab — 设计稿 `screens-3.jsx::RecipesScreen`。
///
/// 4-tab segmented(用临期 / 现有食材 / 探索 / 我的)+ 时间筛选(不限 / ≤15 / ≤30 分钟)。
/// "用临期" 顶部展示橙黄 banner 提醒优先使用临期食材的数量。
enum _RecipeTab { expiring, available, explore, mine }

enum _TimeFilter { all, fast15, fast30 }

const _screenHorizontalPadding = AppSpacing.xl;
const _timeFilterPadding = EdgeInsets.symmetric(
  horizontal: _screenHorizontalPadding,
  vertical: AppSpacing.xs + 2,
);
const _listPadding = EdgeInsets.fromLTRB(
  _screenHorizontalPadding,
  AppSpacing.sm,
  _screenHorizontalPadding,
  120,
);

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  _RecipeTab _tab = _RecipeTab.expiring;
  _TimeFilter _time = _TimeFilter.all;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  void _openCustomRecipeForm() {
    pushRouteOnce(
      context,
      fkRoute<void>(builder: (_) => const CustomRecipeFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(inventoryProvider.select(inventoryNamesSignature));
    ref.watch(inventoryProvider.select(_expiringNamesSignature));
    final inventory = ref.read(inventoryProvider);
    final inventoryNames = inventoryNameSet(inventory);
    final recommended = ref.watch(recommendedRecipesProvider);
    final customRecipes = ref.watch(customRecipesProvider);
    final allAsync = ref.watch(recipesProvider);

    final all = allAsync.maybeWhen(
      data: (data) => data,
      orElse: () => recommended,
    );

    final expiringNames = _expiringIngredientNames(inventory);
    final expiringRecipes = recommended
        .where(
          (r) => r.ingredients.any(
            (ing) => recipeIngredientMatchesInventory(ing, expiringNames),
          ),
        )
        .toList();

    final list = switch (_tab) {
      _RecipeTab.expiring => expiringRecipes,
      _RecipeTab.available => recommended,
      _RecipeTab.explore => all,
      _RecipeTab.mine => customRecipes,
    };

    final filtered = list.where((r) {
      return switch (_time) {
        _TimeFilter.all => true,
        _TimeFilter.fast15 => r.cookingMinutes <= 15,
        _TimeFilter.fast30 => r.cookingMinutes <= 30,
      };
    }).toList();

    final q = _query.trim().toLowerCase();
    final searched = q.isEmpty
        ? filtered
        : filtered
              .where(
                (r) =>
                    r.name.toLowerCase().contains(q) ||
                    r.ingredients.any(
                      (ing) => ing.name.toLowerCase().contains(q),
                    ),
              )
              .toList();

    final fetchFailed = ref
        .watch(recipesFetchProvider)
        .maybeWhen(data: (r) => r.fetchFailed, orElse: () => false);
    // Show the skeleton while a fetch-backed tab is still loading with nothing
    // yet (not just explore), to avoid flashing a misleading empty state on
    // first launch; the local-only `mine` tab keeps its empty state.
    final showSkeleton =
        allAsync.isLoading && searched.isEmpty && _tab != _RecipeTab.mine;
    // On the explore tab, distinguish a real fetch failure from "no recipes".
    final showError =
        fetchFailed && searched.isEmpty && _tab == _RecipeTab.explore;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FkTopBar(
            title: '智能菜谱',
            subtitle: '基于你的冰箱推荐',
            actions: [
              FkIconButton(
                onTap: _openCustomRecipeForm,
                child: const Icon(Icons.add_rounded, size: 18),
              ),
              FkIconButton(
                onTap: _toggleSearch,
                child: Icon(
                  _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  size: 18,
                ),
              ),
            ],
          ),
          if (_searchOpen)
            _RecipeSearchField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
            ),
          _TabRow(selected: _tab, onSelect: (t) => setState(() => _tab = t)),
          _TimeFilterRow(
            selected: _time,
            onSelect: (t) => setState(() => _time = t),
          ),
          if (_tab == _RecipeTab.expiring && expiringRecipes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _screenHorizontalPadding,
                0,
                _screenHorizontalPadding,
                AppSpacing.sm,
              ),
              child: _ExpiringBanner(count: expiringNames.length),
            ),
          Expanded(
            child: showSkeleton
                ? const _RecipeSkeletonList()
                : showError
                ? _RecipeErrorState(
                    onRetry: () => ref.invalidate(recipesFetchProvider),
                  )
                : searched.isEmpty
                ? _EmptyState(tab: _tab, query: q)
                : ListView.separated(
                    padding: _listPadding,
                    itemCount: searched.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) {
                      final recipe = searched[i];
                      final matched = matchedIngredientCountForNames(
                        inventoryNames,
                        recipe,
                      );
                      final useExpiring = _tab == _RecipeTab.expiring;
                      final usesHero = _tab != _RecipeTab.mine;
                      return RecipeCard(
                        recipe: recipe,
                        matchedCount: matched,
                        useExpiring: useExpiring,
                        heroTag: usesHero ? 'recipe-image-${recipe.id}' : null,
                        onTap: () => pushRouteOnce(
                          context,
                          fkRoute<void>(
                            builder: (_) => _tab == _RecipeTab.mine
                                ? CustomRecipeDetailScreen(recipeId: recipe.id)
                                : RecipeDetailScreen(
                                    recipe: recipe,
                                    useExpiring: useExpiring,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 名称小写归一化后的 expiring/expired 食材集合 — 用作"用临期"tab 的匹配键。
  Set<String> _expiringIngredientNames(List<Ingredient> inventory) {
    return inventory
        .where(isNotFreshIngredient)
        .map((i) => i.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  String _expiringNamesSignature(List<Ingredient> inventory) {
    final names = _expiringIngredientNames(inventory).toList()..sort();
    return names.join(' ');
  }
}

class _TabRow extends StatelessWidget {
  final _RecipeTab selected;
  final void Function(_RecipeTab) onSelect;
  const _TabRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tabs = <(_RecipeTab, String, IconData)>[
      (_RecipeTab.expiring, '用临期', Icons.local_fire_department_rounded),
      (_RecipeTab.available, '现有', Icons.eco_rounded),
      (_RecipeTab.explore, '探索', Icons.menu_book_rounded),
      (_RecipeTab.mine, '我的', Icons.bookmark_rounded),
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _screenHorizontalPadding),
      child: Row(
        children: [
          for (final (value, label, icon) in tabs)
            Expanded(
              child: _TabButton(
                icon: icon,
                label: label,
                active: value == selected,
                onTap: () => onSelect(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    return Semantics(
      label: '$label tab',
      selected: active,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              const Positioned(
                left: AppSpacing.xxl,
                right: AppSpacing.xxl,
                bottom: 0,
                child: _ActiveTabIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTabIndicator extends StatelessWidget {
  const _ActiveTabIndicator();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: const SizedBox(height: 2.5),
    );
  }
}

class _TimeFilterRow extends StatelessWidget {
  final _TimeFilter selected;
  final void Function(_TimeFilter) onSelect;
  const _TimeFilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final filters = <(_TimeFilter, String)>[
      (_TimeFilter.all, '不限时间'),
      (_TimeFilter.fast15, '⏱ 15 分钟内'),
      (_TimeFilter.fast30, '⏱ 30 分钟内'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: _timeFilterPadding,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final (value, label) = filters[i];
          final active = value == selected;
          return GestureDetector(
            onTap: () => onSelect(value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.hair,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.onPrimary : AppColors.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ExpiringBanner extends StatelessWidget {
  final int count;
  const _ExpiringBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.fkWarnSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 16,
            color: AppColors.fkWarnInk,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '优先使用 $count 件临期食材',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.fkWarnInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeSkeletonList extends StatelessWidget {
  const _RecipeSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: _listPadding,
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, _) => const FkRecipeSkeletonCard(),
    );
  }
}

class _RecipeSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _RecipeSearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _screenHorizontalPadding,
        0,
        _screenHorizontalPadding,
        AppSpacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                autofocus: true,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  hintText: '搜索菜谱或食材',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _RecipeErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _RecipeErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '菜谱加载失败，请检查网络后重试',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final _RecipeTab tab;
  final String query;

  const _EmptyState({required this.tab, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final msg = query.isNotEmpty
        ? '没有匹配「$query」的菜谱'
        : switch (tab) {
            _RecipeTab.expiring => '没有临期食材,先去添加几样吧',
            _RecipeTab.available => '冰箱里加点食材,菜谱就来啦',
            _RecipeTab.explore => '暂无可探索的菜谱',
            _RecipeTab.mine => '还没有保存的食谱，点右上角 + 创建',
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.huge),
        child: Text(
          msg,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
