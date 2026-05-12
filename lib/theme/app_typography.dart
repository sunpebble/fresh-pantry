import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 字号 token，对应 [AppTypography.textTheme] 的尺寸阶梯。
/// 优先使用 `Theme.of(context).textTheme.xxx`；本 token 用于 inline `TextStyle`
/// 中无法直接套 textTheme 的场景，确保字号始终落在阶梯上。
class AppFontSize {
  AppFontSize._();

  static const double xs = 11; // labelSmall
  static const double sm = 12; // bodySmall / labelMedium
  static const double md = 14; // bodyMedium / titleSmall / labelLarge
  static const double lg = 16; // bodyLarge / titleMedium
  static const double xl = 20; // titleLarge / headlineSmall
  static const double xxl = 24; // displaySmall / headlineMedium
  static const double xxxl = 28; // displayMedium / headlineLarge
  static const double huge = 32; // displayLarge
}

class AppTypography {
  static TextTheme get textTheme {
    return TextTheme(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
      displaySmall: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static TextStyle get sectionTitle =>
      textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800);

  /// Hero block 大数字(Dashboard / Shopping 进度卡)。
  static TextStyle get heroStat => GoogleFonts.plusJakartaSans(
        fontSize: 56,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        height: 1,
      );

  /// 中量级 hero 数字(Detail 数量 / 剩余天数)。
  static TextStyle get heroSubStat => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      );

  /// FK Top bar 标题。
  static TextStyle get sectionTitleLg => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );
}
