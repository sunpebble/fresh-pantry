import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 全 App 统一的页面转场 —— 目标页上移淡入,基调克制·高级。
///
/// 替代裸 [MaterialPageRoute],让全 App 导航有一致的「设计过的」转场。
/// 尊重「减弱动态效果」:[MediaQuery.disableAnimationsOf] 为真时只淡入(不位移),
/// 配合系统无障碍。
PageRouteBuilder<T> fkRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: AppDuration.page,
    reverseTransitionDuration: AppDuration.page,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurves.emphasized,
        reverseCurve: AppMotionCurves.emphasized,
      );
      if (reduceMotion) {
        return FadeTransition(opacity: curved, child: child);
      }
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
