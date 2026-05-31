import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'fk_pressable.dart';

/// 统一勾选圈 —— 选中填充 + 勾,按压缩放,带选择触感。
class FkCheckCircle extends StatelessWidget {
  const FkCheckCircle({
    super.key,
    required this.checked,
    required this.onTap,
    this.size = 28,
  });

  final bool checked;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return FkAnimatedPressable(
      onTap: onTap,
      haptic: HapticKind.selection,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppDuration.normal,
        curve: AppMotionCurves.standard,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: checked ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: checked ? AppColors.primary : AppColors.outline,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: checked
            ? Icon(
                Icons.check_rounded,
                size: size * 0.6,
                color: AppColors.onPrimary,
              )
            : null,
      ),
    );
  }
}
