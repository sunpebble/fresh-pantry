import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 设计稿 Hero block — Dashboard / Shopping 进度卡 / Detail 共用的渐变大顶。
///
/// 默认 primary → primaryDark 线性渐变,底部圆角 28(只圆下面两角)。可选
/// 装饰圆斑(`showDecorations: true` 渲染两枚白色低透明度圆)。
class FkHeroHeader extends StatelessWidget {
  final Widget child;
  final List<Color> gradient;
  final double bottomRadius;
  final EdgeInsetsGeometry padding;
  final bool showDecorations;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const FkHeroHeader({
    super.key,
    required this.child,
    this.gradient = const [AppColors.primary, AppColors.primaryContainer],
    this.bottomRadius = AppRadius.hero,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.xxl,
      AppSpacing.xl,
      80,
    ),
    this.showDecorations = true,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(bottomRadius),
        bottomRight: Radius.circular(bottomRadius),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: begin, end: end, colors: gradient),
        ),
        child: Stack(
          children: [
            if (showDecorations) ...[
              Positioned(
                right: -40,
                top: -30,
                child: _Blob(180, Colors.white.withValues(alpha: 0.07)),
              ),
              Positioned(
                right: 30,
                top: 60,
                child: _Blob(60, Colors.white.withValues(alpha: 0.09)),
              ),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob(this.size, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
