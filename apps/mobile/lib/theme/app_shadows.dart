import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 投影 token —— 统一软阴影层级,替代散落的内联 BoxShadow。
class AppShadows {
  AppShadows._();

  /// 卡片默认软阴影(FkCard):近距 1px + 远距 16px 两层。
  static const List<BoxShadow> card = [
    BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: AppColors.shadowSoft,
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// 小尺寸柔和阴影(icon button / 小卡 / stat card)。
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: AppColors.shadowSoft,
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// 强调投影(primary FAB / 底部导航中央按钮)。
  static const List<BoxShadow> strong = [
    BoxShadow(
      color: AppColors.shadowWarm,
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}
