import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'fk_pressable.dart';

/// 项目通用 pill 样式 chip,支持可选 leading icon、可选选中态、可选点击。
///
/// 颜色解析顺序:
/// 1. 显式传入的 [backgroundColor] / [foregroundColor]
/// 2. [selected] 时 fallback 到 [selectedBackgroundColor] /
///    [selectedForegroundColor];否则使用默认 surfaceContainerLow / onSurface 配色
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    this.iconSize = 16,
    this.iconForegroundColor,
    this.iconLabelGap = 6,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
    this.backgroundColor,
    this.foregroundColor,
    this.selectedBackgroundColor,
    this.selectedForegroundColor,
    this.borderColor,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double iconSize;

  /// 单独控制 icon 颜色;为 null 时跟随文本颜色
  final Color? iconForegroundColor;

  /// icon 与 label 间的水平间距
  final double iconLabelGap;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? selectedBackgroundColor;
  final Color? selectedForegroundColor;

  /// 可选边框颜色(例如建议态)
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final defaultBg = selected
        ? (selectedBackgroundColor ?? AppColors.primary)
        : (backgroundColor ?? AppColors.surfaceContainerLow);
    final defaultFg = selected
        ? (selectedForegroundColor ?? AppColors.onPrimary)
        : (foregroundColor ?? AppColors.onSurfaceVariant);
    final iconColor = iconForegroundColor ?? defaultFg;

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: defaultBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: iconColor),
            SizedBox(width: iconLabelGap),
          ],
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: defaultFg,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return FkAnimatedPressable(onTap: onTap, child: body);
  }
}
