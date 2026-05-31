import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_pressable.dart';

/// 设计稿 `ui.jsx::FKIconBtn` — 圆形单 icon 按钮。
///
/// 默认 36×36 白底 + 1px 软阴影。`primary: true` 切到 52×52 矢车菊蓝填充 +
/// 暖灰棕投影(底栏中央 add 用)。`onImage: true` 时切到半透明白底(详情页
/// hero 上的 back / 收藏按钮)。
class FkIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool primary;
  final bool onImage;
  final List<BoxShadow>? shadows;

  const FkIconButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 36,
    this.backgroundColor,
    this.foregroundColor,
    this.primary = false,
    this.onImage = false,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? AppColors.primary
        : (onImage
              ? Colors.white.withValues(alpha: 0.95)
              : (backgroundColor ?? Colors.white));
    final fg = primary
        ? Colors.white
        : (foregroundColor ?? AppColors.onSurface);
    final effectiveShadow =
        shadows ??
        (primary
            ? AppShadows.strong
            : const [
                BoxShadow(
                  color: AppColors.subtleShadow,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]);
    final box = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: effectiveShadow,
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: fg, size: primary ? 26 : 18),
        child: child,
      ),
    );
    if (onTap == null) return box;
    return FkAnimatedPressable(onTap: onTap, child: box);
  }
}
