import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';

/// 食材 / 菜谱 / 购物清单的状态枚举。语义见 `data.jsx::FK_STATUS_LABEL`。
enum FkStatus { fresh, soon, urgent, expired, low }

class FkStatusStyle {
  final Color bg;
  final Color fg;
  final String label;
  const FkStatusStyle(this.bg, this.fg, this.label);
}

const Map<FkStatus, FkStatusStyle> kFkStatusStyles = {
  FkStatus.fresh: FkStatusStyle(
    AppColors.primarySoft,
    AppColors.primaryContainer,
    '新鲜',
  ),
  FkStatus.soon: FkStatusStyle(
    AppColors.fkWarnSoft,
    AppColors.onSecondaryContainer,
    '即将过期',
  ),
  FkStatus.urgent: FkStatusStyle(
    AppColors.fkDangerSoft,
    AppColors.onTertiaryContainer,
    '快过期',
  ),
  FkStatus.expired: FkStatusStyle(AppColors.fkDanger, Colors.white, '已过期'),
  FkStatus.low: FkStatusStyle(
    AppColors.fkDangerSoft,
    AppColors.onTertiaryContainer,
    '库存不足',
  ),
};

/// `FreshnessState`(领域模型)→ `FkStatus`(UI 状态)的唯一映射。
///
/// 各页面据此从 [kFkStatusStyles] 取状态配色,避免在卡片 / 行 / 徽章里各自
/// 硬编码「过期 vs 非过期」的二分逻辑(会丢失 urgent 珊瑚 与 soon 黄油的区分)。
extension FreshnessStatusX on FreshnessState {
  FkStatus get fkStatus => switch (this) {
    FreshnessState.fresh => FkStatus.fresh,
    FreshnessState.expiringSoon => FkStatus.soon,
    FreshnessState.urgent => FkStatus.urgent,
    FreshnessState.expired => FkStatus.expired,
  };

  FkStatusStyle get statusStyle => kFkStatusStyles[fkStatus]!;
}

/// FK 圆形小标签 — 设计稿 `ui.jsx::FKPill`。
///
/// 默认是 `surfaceContainer` (#F0EBE3) 底 + ink 文字,12/600。`sm: true` 时
/// padding 与字号会更紧凑,用于卡内 inline 显示。
class FkPill extends StatelessWidget {
  final String label;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool sm;
  final VoidCallback? onTap;
  final BorderSide? border;

  const FkPill({
    super.key,
    required this.label,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.sm = false,
    this.onTap,
    this.border,
  });

  /// 直接从 `FkStatus` 构造一个状态 pill。
  factory FkPill.status(FkStatus status, {bool sm = false}) {
    final s = kFkStatusStyles[status]!;
    return FkPill(
      label: s.label,
      backgroundColor: s.bg,
      foregroundColor: s.fg,
      sm: sm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.surfaceContainer;
    final fg = foregroundColor ?? AppColors.onSurfaceVariant;
    final body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: sm ? 8 : 10,
        vertical: sm ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border != null ? Border.fromBorderSide(border!) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(color: fg, size: sm ? 11 : 12),
              child: leading!,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: sm ? AppFontSize.xs : AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: -0.1,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}
