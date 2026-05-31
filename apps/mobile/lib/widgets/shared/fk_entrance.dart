import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 列表项入场动画 —— 淡入 + 上移,带 index 交错。
///
/// 一次性播放(每个 element 实例只播一次,不随滚动重放)。
/// 尊重「减弱动态效果」:[MediaQuery.disableAnimationsOf] 为真时立即终态。
class FkEntrance extends StatefulWidget {
  const FkEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration,
  });

  final Widget child;
  final int index;
  final Duration? duration;

  @override
  State<FkEntrance> createState() => _FkEntranceState();
}

class _FkEntranceState extends State<FkEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.duration ?? AppDuration.slow;
    _controller = AnimationController(vsync: this, duration: duration);
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.standard,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.value = 1.0;
      return;
    }
    final delay =
        AppMotion.staggerStep *
        widget.index.clamp(0, AppMotion.staggerMaxItems);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      // 立即终态,但保持与动画分支一致的 Opacity 结构(opacity 1.0,无害)。
      return Opacity(opacity: 1.0, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _opacity.value) * AppMotion.entranceOffset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
