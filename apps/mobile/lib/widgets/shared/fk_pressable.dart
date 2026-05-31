import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// 触感强度。统一三档,屏幕只挑语义不挑 API。
enum HapticKind { selection, light, none }

/// 通用按压包装器 —— 按下缩放 + 触感,松手回弹。
///
/// 设计基调「克制·高级」:缩放仅 0.97,时长 [AppDuration.fast]。
/// 尊重系统「减弱动态效果」:[MediaQuery.disableAnimationsOf] 为真时跳过缩放,
/// 仅保留点击与触感(也避免无限/隐式动画卡住 widget 测试的 pumpAndSettle)。
class FkAnimatedPressable extends StatefulWidget {
  const FkAnimatedPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = AppMotion.pressScale,
    this.haptic = HapticKind.selection,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final HapticKind haptic;
  final HitTestBehavior behavior;

  @override
  State<FkAnimatedPressable> createState() => _FkAnimatedPressableState();
}

class _FkAnimatedPressableState extends State<FkAnimatedPressable> {
  bool _pressed = false;

  void _fireHaptic() {
    switch (widget.haptic) {
      case HapticKind.selection:
        HapticFeedback.selectionClick();
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.none:
        break;
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final gesture = GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap == null
          ? null
          : () {
              _fireHaptic();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      onTapDown: enabled && !reduceMotion ? (_) => _setPressed(true) : null,
      onTapUp: enabled && !reduceMotion ? (_) => _setPressed(false) : null,
      onTapCancel: enabled && !reduceMotion ? () => _setPressed(false) : null,
      child: widget.child,
    );

    if (reduceMotion) return gesture;

    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1.0,
      duration: AppDuration.fast,
      curve: AppMotionCurves.standard,
      child: gesture,
    );
  }
}
