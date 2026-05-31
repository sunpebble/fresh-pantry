import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_pressable.dart';

/// FreshKeeper 主卡 — 圆角 20、白底、两层软阴影。
///
/// 设计稿同名件:`ui.jsx::FKCard`。`gradient` 与 `backgroundColor` 互斥;
/// 传 `gradient` 时背景色被忽略,适合 Shopping 进度卡这种大渐变面。
class FkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double borderRadius;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;

  const FkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.backgroundColor,
    this.borderRadius = AppRadius.xl,
    this.gradient,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? (backgroundColor ?? AppColors.surfaceContainerLowest)
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows ?? AppShadows.card,
      ),
      child: child,
    );
    if (onTap == null) return inner;
    return FkAnimatedPressable(onTap: onTap, child: inner);
  }
}
