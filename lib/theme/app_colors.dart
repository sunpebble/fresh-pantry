import 'package:flutter/material.dart';

class AppColors {
  // ─── FK Primary · cornflower blue ───
  static const primary = Color(0xFF5B7FD4);
  static const primaryContainer = Color(0xFF3F60B5);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onPrimaryContainer = Color(0xFFE5ECFA);
  static const primaryFixed = Color(0xFFE5ECFA);
  static const primaryLight = Color(0xFF8AA3E0);
  static const primarySoft = Color(0xFFE5ECFA);

  // ─── Warn · butter yellow (临期) ───
  static const secondary = Color(0xFFFFC857);
  static const secondaryContainer = Color(0xFFFFF3D6);
  static const onSecondary = Color(0xFF2D2438);
  static const onSecondaryContainer = Color(0xFF9B7A2A);
  static const secondaryFixed = Color(0xFFFFF3D6);

  // ─── Danger · coral (过期 / 不足) — 复用 tertiary 字段名,语义为 danger ───
  static const tertiary = Color(0xFFE76F51);
  static const tertiaryContainer = Color(0xFFFBE0D7);
  static const onTertiary = Color(0xFFFFFFFF);
  static const onTertiaryContainer = Color(0xFFB5523A);
  static const tertiaryFixedDim = Color(0xFFFFC857);

  // 语义别名 — 新代码偏好使用 fk* 前缀
  static const fkWarn = secondary;
  static const fkWarnSoft = secondaryContainer;
  static const fkDanger = tertiary;
  static const fkDangerSoft = tertiaryContainer;

  // Error
  static const error = Color(0xFFE76F51);
  static const errorContainer = Color(0xFFFBE0D7);
  static const onError = Color(0xFFFFFFFF);
  static const onErrorContainer = Color(0xFFB5523A);

  // Surface · warm cream
  static const surface = Color(0xFFFBF8F3);
  static const surfaceDim = Color(0xFFE8E3DA);
  static const surfaceBright = Color(0xFFFFFFFF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF6F2EB);
  static const surfaceContainer = Color(0xFFF0EBE3);
  static const surfaceContainerHigh = Color(0xFFE9E2D6);
  static const surfaceContainerHighest = Color(0xFFE3DCCB);

  // On-surface · deep plum-ink
  static const onSurface = Color(0xFF2D2438);
  static const onSurfaceVariant = Color(0xFF4F4358);
  static const outline = Color(0xFF9B92A5);
  static const outlineVariant = Color(0xFFC7C1CE);
  static const hair = Color(0x142D2438);

  // Semantic
  static const urgentAttentionBackground = Color(0xFFFBE0D7);
  static const onTertiaryFixedDim = Color(0xFF9B7A2A);

  // Inverse
  static const inverseSurface = Color(0xFF2D2438);
  static const inverseOnSurface = Color(0xFFF6F2EB);
  static const inversePrimary = Color(0xFF8AA3E0);

  // AI accents — primary family
  static const aiAccent = primary;
  static const aiAccentMuted = outline;
  static const aiGradientStart = primary;
  static const aiGradientEnd = primaryContainer;

  // Overlays / shadows
  static const onImageScrim = Color(0x33000000);
  static const onImageBorderStrong = Color(0xB3FFFFFF);
  static const onImageBorderSoft = Color(0x99FFFFFF);
  static const modalBarrier = Color(0x47000000);
  static const subtleShadow = Color(0x0F000000);

  // FK 暖灰棕投影 — 替代旧 primary 紫色光晕
  static const shadowWarm = Color(0x293C2D1E); // rgba(60,45,30,0.16)
  static const shadowSoft = Color(0x0A263A34); // 软阴影
}
