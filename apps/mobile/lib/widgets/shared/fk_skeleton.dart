import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 骨架积木 —— 纯色圆角块,尺寸由调用方给。配合 [FkShimmer] 扫光。
class FkSkeletonBox extends StatelessWidget {
  const FkSkeletonBox({super.key, this.width, this.height = 16, this.radius});

  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.sm),
      ),
    );
  }
}

/// 骨架文本行 —— 高度固定,默认满宽。
class FkSkeletonLine extends StatelessWidget {
  const FkSkeletonLine({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FkSkeletonBox(width: width, height: height, radius: AppRadius.xs);
  }
}
