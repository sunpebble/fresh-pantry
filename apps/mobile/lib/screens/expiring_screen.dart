import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_snackbar.dart';
import '../utils/page_transitions.dart';
import '../utils/safe_push.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_empty_state.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'ingredient_detail_screen.dart';
import 'settings_screen.dart';

class ExpiringScreen extends ConsumerWidget {
  const ExpiringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiredCount = ref.watch(
      expiringItemsProvider.select(
        (items) => items.where((i) => i.state == FreshnessState.expired).length,
      ),
    );
    final urgentCount = ref.watch(
      expiringItemsProvider.select(
        (items) => items.where((i) => i.state == FreshnessState.urgent).length,
      ),
    );
    final soonCount = ref.watch(
      expiringItemsProvider.select(
        (items) =>
            items.where((i) => i.state == FreshnessState.expiringSoon).length,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            FkTopBar(
              title: '临期提醒',
              subtitle: '按状态分组 · 优先处理高亮项',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: _RemindShortcut(
                onTap: () => Navigator.of(
                  context,
                ).push(fkRoute<void>(builder: (_) => const SettingsScreen())),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (expiredCount == 0 && urgentCount == 0 && soonCount == 0)
              const FkEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: '没有临期食材',
                subtitle: '冰箱状态健康,继续保持!',
              )
            else ...[
              if (expiredCount > 0)
                const _Group(
                  title: '已过期 / 今天到期',
                  filter: FreshnessState.expired,
                  dotColor: AppColors.fkDanger,
                ),
              if (urgentCount > 0)
                const _Group(
                  title: '快过期',
                  filter: FreshnessState.urgent,
                  dotColor: AppColors.fkDanger,
                ),
              if (soonCount > 0)
                const _Group(
                  title: '即将过期',
                  filter: FreshnessState.expiringSoon,
                  dotColor: AppColors.fkWarn,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemindShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _RemindShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return FkCard(
      backgroundColor: AppColors.primarySoft,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.notifications_outlined,
                  size: 18,
                  color: AppColors.primaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提醒已开启',
                  style: tt.labelLarge?.copyWith(
                    fontSize: AppFontSize.xs + 2,
                    color: AppColors.primaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '提前 1 天 · 每日 9:00 提醒',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.primaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.primaryContainer,
          ),
        ],
      ),
    );
  }
}

class _Group extends ConsumerWidget {
  final String title;
  final FreshnessState filter;
  final Color dotColor;

  const _Group({
    required this.title,
    required this.filter,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(
      expiringItemsProvider.select(
        (all) => all.where((i) => i.state == filter).toList(),
      ),
    );
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: Row(
              children: [
                SizedBox(
                  width: 8,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: tt.labelLarge?.copyWith(color: AppColors.onSurface),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${items.length} 件',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _ExpiringRow(item: items[i], isLast: i == items.length - 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiringRow extends ConsumerWidget {
  final Ingredient item;
  final bool isLast;
  const _ExpiringRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catId = fkCategoryIdFor(item.category);
    final palette = FkCategoryPalette.of(catId);
    // 走单一状态色来源,保留 urgent(珊瑚)与 soon(黄油)的区分。
    final style = item.state.statusStyle;
    final pillBg = style.bg;
    final pillFg = style.fg;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.hair, width: 0.5),
              ),
      ),
      child: Column(
        children: [
          Semantics(
            label: '查看 ${item.name} 详情',
            button: true,
            child: GestureDetector(
              onTap: () => pushRouteOnce(
                context,
                fkRoute<void>(
                  builder: (_) => IngredientDetailScreen(ingredient: item),
                ),
              ),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: palette.tint,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: CatIcon(
                      category: catId,
                      size: 28,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: tt.labelLarge?.copyWith(
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.quantity}${item.unit} · ${storageLabelFor(item.storage)}',
                          style: tt.labelSmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.expiryLabel != null)
                    FkPill(
                      label: item.expiryLabel!,
                      backgroundColor: pillBg,
                      foregroundColor: pillFg,
                      sm: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Row(
              children: [
                _MiniBtn(
                  icon: Icons.check_rounded,
                  label: '用了',
                  soft: true,
                  onTap: () => _markUsed(context, ref),
                ),
                const SizedBox(width: AppSpacing.sm),
                _MiniBtn(
                  icon: Icons.shopping_cart_outlined,
                  label: '加购',
                  onTap: () => _addToShopping(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markUsed(BuildContext context, WidgetRef ref) async {
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
    if (index == -1) {
      showAppSnackBar(context, '未找到「${item.name}」库存项');
      return;
    }
    final removed = ref.read(inventoryProvider)[index];
    try {
      await ref.read(inventoryProvider.notifier).remove(index);
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, '操作失败，请重试');
      return;
    }
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      '「${item.name}」已标记使用',
      backgroundColor: AppColors.primary,
      actionLabel: '撤销',
      actionTextColor: AppColors.onPrimary,
      onAction: () async {
        try {
          await ref.read(inventoryProvider.notifier).insertAt(index, removed);
        } catch (_) {
          if (context.mounted) showAppSnackBar(context, '撤销失败，请重试');
        }
      },
    );
  }

  Future<void> _addToShopping(BuildContext context, WidgetRef ref) async {
    try {
      final added = await ref
          .read(shoppingProvider.notifier)
          .addFromIngredient(item);
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
        backgroundColor: added ? AppColors.primary : AppColors.tertiary,
      );
    } catch (_) {
      if (!context.mounted) return;
      showAppSnackBar(context, '加入购物清单失败，请重试');
    }
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool soft;
  final VoidCallback onTap;
  const _MiniBtn({
    required this.icon,
    required this.label,
    this.soft = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = soft ? AppColors.primarySoft : AppColors.surfaceContainer;
    final fg = soft ? AppColors.primaryContainer : AppColors.onSurface;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 3),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

