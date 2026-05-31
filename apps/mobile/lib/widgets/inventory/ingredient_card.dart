import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';
import '../../theme/fk_category_palette.dart';
import '../../utils/storage_labels.dart';
import '../shared/cat_icon.dart';
import '../shared/category_icon.dart';
import '../shared/fk_pill.dart';
import '../shared/fk_pressable.dart';
import '../shared/zone_icon.dart';

/// 旧 API:freshness 状态 → 徽章配色。保留供未迁移的 caller(测试)读取。
/// 现委托给单一来源 [kFkStatusStyles](经 `FreshnessState.statusStyle`)。
({Color bg, Color text}) freshnessBadgeColors(FreshnessState state) {
  final s = state.statusStyle;
  return (bg: s.bg, text: s.fg);
}

/// 食材卡片 — 设计稿 `screens-2.jsx::IngredientCard`。
///
/// 适配 2-col grid 的紧凑布局:CatIcon avatar + 名称 + qty/zone + 底部 4px 进度
/// 条 + 右上 status pill。`onBuyAgain` 保留但被折叠到底部 inline 行(非 fresh 才显示)。
class IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback? onBuyAgain;
  final VoidCallback? onTap;

  /// Optional Hero tag for the category-icon avatar. When non-null the avatar
  /// is wrapped in a [Hero] so it can fly to the detail screen. Callers that
  /// render multiple cards (the inventory grid) must supply a unique tag per
  /// card; omitting the tag (the default) is safe and produces no Hero at all.
  final Object? heroTag;

  const IngredientCard({
    super.key,
    required this.ingredient,
    this.onBuyAgain,
    this.onTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final state = ingredient.state;
    final isFresh = state == FreshnessState.fresh;
    final isExpired = state == FreshnessState.expired;
    final catId = fkCategoryIdFor(ingredient.category);
    final palette = FkCategoryPalette.of(catId);
    final statusBadge = _statusBadgeFor(state, ingredient.expiryLabel);
    final progress = ingredient.freshnessPercent.clamp(0.0, 1.0);
    // 设计稿进度条用状态 ink 色(expired 因 ink 为白,退回用 bg = 珊瑚)。
    final style = state.statusStyle;
    final progressColor = isExpired ? style.bg : style.fg;

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(catId, palette),
              const Spacer(),
              ?statusBadge,
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ingredient.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface.withValues(
                alpha: isExpired ? 0.6 : 1.0,
              ),
            ),
          ),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              height: 1.2,
            ),
            child: Row(
              children: [
                Text('${ingredient.quantity}${ingredient.unit} · '),
                ZoneIcon(
                  zone: _zoneId(ingredient.storage),
                  size: 12,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    storageLabelFor(ingredient.storage),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(2),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.05, 1.0)),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppDuration.slow,
              curve: AppMotionCurves.standard,
              builder: (context, value, child) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: child,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          if (onBuyAgain != null && !isFresh) ...[
            const SizedBox(height: 10),
            FkAnimatedPressable(
              onTap: onBuyAgain,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '加购',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return FkAnimatedPressable(onTap: onTap, child: card);
  }

  Widget _buildAvatar(String catId, FkCatColors palette) {
    final avatar = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: CatIcon(category: catId, size: 30, color: palette.ink),
      ),
    );
    if (heroTag == null) return avatar;
    return Hero(tag: heroTag!, child: avatar);
  }

  /// 右上小角徽 — 设计稿用 expiryLabel 作为内容;fresh 状态不显示。
  Widget? _statusBadgeFor(FreshnessState state, String? expiryLabel) {
    if (state == FreshnessState.fresh) return null;
    final label = expiryLabel ?? _defaultLabel(state);
    final colors = freshnessBadgeColors(state);
    return FkPill(
      label: label.toUpperCase(),
      backgroundColor: colors.bg,
      foregroundColor: colors.text,
      sm: true,
    );
  }

  String _defaultLabel(FreshnessState state) => switch (state) {
    FreshnessState.expiringSoon => '即将过期',
    FreshnessState.urgent => '快过期',
    FreshnessState.expired => '已过期',
    FreshnessState.fresh => '新鲜',
  };

  /// 把 Ingredient 的 storage(IconType.fridge / pantry / ...)映射到 FK zone id。
  String _zoneId(dynamic storage) {
    final name = storage.toString().split('.').last;
    return switch (name) {
      'fridge' => 'fridge',
      'freezer' => 'freezer',
      'pantry' => 'pantry',
      _ => 'fridge',
    };
  }
}
