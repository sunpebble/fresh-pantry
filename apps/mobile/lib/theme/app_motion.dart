import 'package:flutter/animation.dart';

/// 动效时长 token。集中所有动画时长,杜绝散落的魔法数字。
/// 基调:克制·高级 —— 快而不急,平稳收尾。
class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 120); // 按压 / 微反馈
  static const Duration normal = Duration(milliseconds: 180); // 折叠 / 状态切换
  static const Duration slow = Duration(milliseconds: 250); // 入场 / cross-fade
  static const Duration page = Duration(milliseconds: 240); // 页面转场
  static const Duration shimmer = Duration(milliseconds: 1400); // 微光循环
}

/// 动效曲线 token。统一缓动,避免逐处自定义。
class AppMotionCurves {
  AppMotionCurves._();

  static const Curve standard = Curves.easeOutCubic; // 默认:平稳减速
  static const Curve decelerate = Curves.easeOut; // 轻量淡入
  static const Curve emphasized = Cubic(0.2, 0, 0, 1); // 页面转场:强调减速
}

/// 动效参数 token（位移幅度、交错节奏、按压缩放）。
class AppMotion {
  AppMotion._();

  static const double pressScale = 0.97; // 按压缩放终值
  static const double entranceOffset = 8; // 入场上移像素
  static const Duration staggerStep = Duration(milliseconds: 50); // 列表交错步长
  static const int staggerMaxItems = 8; // 交错封顶,避免后段延迟过长
}
