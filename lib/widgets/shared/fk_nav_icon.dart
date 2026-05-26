import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';

/// FreshKeeper 底部导航 5 个 tab 的卡通线性 SVG icon。
///
/// SVG paths 移植自设计稿 `ui.jsx::NavIcon` / `FKTabBar` — 24×24 viewBox、
/// strokeWidth 1.7、round cap & join。`fridge` 与 [ZoneIcon] 冷藏区图标一致。
class FkNavIcon extends StatelessWidget {
  final String icon;
  final double size;
  final Color color;
  final double strokeWidth;

  const FkNavIcon({
    super.key,
    required this.icon,
    this.size = 22,
    this.color = AppColors.outline,
    this.strokeWidth = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    final svg = _kNavSvg[icon] ?? _kNavSvg['home']!;
    final hex = _hex(color);
    final styled = svg
        .replaceAll('{stroke}', hex)
        .replaceAll('{fill}', hex)
        .replaceAll('{sw}', strokeWidth.toString());
    return SvgPicture.string(
      styled,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

String _hex(Color c) {
  final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

const Map<String, String> _kNavSvg = {
  'home': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M5 10.5 12 4.5 19 10.5"/>
    <path d="M7 10.5V20h10V10.5"/>
    <path d="M10 20v-4h4v4"/>
  </g>
</svg>
''',
  'fridge': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/>
    <path d="M4 11h16M8 7v1M8 14v2"/>
  </g>
</svg>
''',
  'recipes': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M7 4h11a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"/>
    <path d="M8 4v16"/>
    <path d="M11 9h6M11 12h6M11 15h4"/>
  </g>
</svg>
''',
  'shopping': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M7 7h11.5l-1.8 8H9.2L7 7z"/>
    <path d="M7 7H5"/>
    <path d="M10 19a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"/>
    <path d="M17 19a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"/>
  </g>
</svg>
''',
  'add': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round">
    <path d="M12 8v8"/>
    <path d="M8 12h8"/>
  </g>
</svg>
''',
};

const List<String> kFkNavIconIds = [
  'home',
  'fridge',
  'recipes',
  'shopping',
  'add',
];
