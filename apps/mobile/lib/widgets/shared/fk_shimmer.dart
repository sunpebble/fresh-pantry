import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 微光扫掠容器 —— 给骨架(或任意 child)叠一层左右移动的高光渐变。
///
/// 尊重「减弱动态效果」:reduce-motion 时不启动循环(controller 不 repeat),
/// 直接显示静态 child —— 既是无障碍,也避免 pumpAndSettle 永不返回。
class FkShimmer extends StatefulWidget {
  const FkShimmer({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<FkShimmer> createState() => _FkShimmerState();
}

class _FkShimmerState extends State<FkShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDuration.shimmer,
    );
    // NOTE: Do NOT call _controller.repeat() here.
    // reduce-motion is read from MediaQuery in didChangeDependencies so the
    // test's MediaQueryData(disableAnimations: true) is respected before the
    // first frame — preventing pumpAndSettle from hanging.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.enabled && !reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || !widget.enabled) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final dx = bounds.width * (_controller.value * 2 - 1);
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surfaceContainerHigh,
                AppColors.surfaceBright,
                AppColors.surfaceContainerHigh,
              ],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlideGradient(dx),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 渐变水平平移 —— 给 shimmer 高光位置加偏移。
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}
