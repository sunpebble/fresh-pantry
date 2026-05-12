import 'package:flutter/material.dart';

/// FreshKeeper 食材分类语义色板。
///
/// 每个分类提供 `tint`(avatar 背景 / 软底)与 `ink`(描边 / 文字 / icon)。
/// 命名与设计稿 `data.jsx::FK_CATEGORIES` 一致(veg / fruit / meat / sea / dairy /
/// drink / sauce / grain / snack),便于查阅。
class FkCatColors {
  final Color tint;
  final Color ink;
  const FkCatColors(this.tint, this.ink);
}

class FkCategoryPalette {
  FkCategoryPalette._();

  static const veg = FkCatColors(Color(0xFFE8F3E1), Color(0xFF4F7A3A));
  static const fruit = FkCatColors(Color(0xFFFBE0D7), Color(0xFFB5523A));
  static const meat = FkCatColors(Color(0xFFFDD6CE), Color(0xFFA8442C));
  static const sea = FkCatColors(Color(0xFFD6EBF2), Color(0xFF3F7691));
  static const dairy = FkCatColors(Color(0xFFE5ECFA), Color(0xFF3F60B5));
  static const drink = FkCatColors(Color(0xFFE2EAF5), Color(0xFF4A5E91));
  static const sauce = FkCatColors(Color(0xFFF0EBE3), Color(0xFF7A6748));
  static const grain = FkCatColors(Color(0xFFFFF3D6), Color(0xFF9B7A2A));
  static const snack = FkCatColors(Color(0xFFFBE3CE), Color(0xFFA85F2C));

  static const Map<String, FkCatColors> all = {
    'veg': veg,
    'fruit': fruit,
    'meat': meat,
    'sea': sea,
    'dairy': dairy,
    'drink': drink,
    'sauce': sauce,
    'grain': grain,
    'snack': snack,
  };

  static FkCatColors of(String catId) => all[catId] ?? grain;

  /// 分类中文名(与设计稿 `data.jsx::FK_CATEGORIES.name` 一致)。
  static const Map<String, String> names = {
    'veg': '蔬菜',
    'fruit': '水果',
    'meat': '肉类',
    'sea': '海鲜',
    'dairy': '乳制品',
    'drink': '饮料',
    'sauce': '调味品',
    'grain': '主食',
    'snack': '零食',
  };
}
