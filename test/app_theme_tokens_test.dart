import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AppSpacing tokens', () {
    test('canonical spacing values match contract', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 20);
      expect(AppSpacing.xxl, 24);
      expect(AppSpacing.xxxl, 28);
      expect(AppSpacing.huge, 32);
    });
  });

  group('AppRadius tokens', () {
    test('canonical radius values match contract', () {
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 20);
      expect(AppRadius.xxl, 24);
      expect(AppRadius.hero, 28);
      expect(AppRadius.chip, 14);
      expect(AppRadius.pill, 999);
    });
  });

  group('AppTypography.sectionTitle', () {
    testWidgets('is titleMedium with FontWeight.w800, same family and size', (
      tester,
    ) async {
      final sectionTitle = AppTypography.sectionTitle;
      final titleMedium = AppTypography.textTheme.titleMedium!;
      expect(sectionTitle.fontWeight, FontWeight.w800);
      expect(sectionTitle.fontSize, titleMedium.fontSize);
      expect(sectionTitle.fontFamily, titleMedium.fontFamily);
    });
  });

  group('AppTheme cardTheme', () {
    testWidgets('elevation is 0 (flat surfaces by design)', (tester) async {
      final cardTheme = AppTheme.lightTheme.cardTheme;
      expect(cardTheme.elevation, 0);
    });

    testWidgets('uses AppRadius.xl (20) with no border (FK soft-shadow style)', (
      tester,
    ) async {
      final cardTheme = AppTheme.lightTheme.cardTheme;
      final shape = cardTheme.shape as RoundedRectangleBorder;
      final radius = (shape.borderRadius as BorderRadius).topLeft.x;
      expect(radius, AppRadius.xl);
      expect(shape.side, BorderSide.none);
    });

    testWidgets('uses surfaceContainerLowest as default color', (tester) async {
      final cardTheme = AppTheme.lightTheme.cardTheme;
      expect(cardTheme.color, AppColors.surfaceContainerLowest);
    });
  });

  group('AppTheme chipTheme', () {
    testWidgets('uses surfaceContainer as default backgroundColor (FK bgAlt)', (
      tester,
    ) async {
      final chipTheme = AppTheme.lightTheme.chipTheme;
      expect(chipTheme.backgroundColor, AppColors.surfaceContainer);
    });

    testWidgets('uses primary as selectedColor', (tester) async {
      final chipTheme = AppTheme.lightTheme.chipTheme;
      expect(chipTheme.selectedColor, AppColors.primary);
    });

    testWidgets('uses StadiumBorder shape', (tester) async {
      final chipTheme = AppTheme.lightTheme.chipTheme;
      expect(chipTheme.shape, isA<StadiumBorder>());
    });
  });

  group('AppColors FK palette', () {
    test('primary is FK cornflower blue', () {
      expect(AppColors.primary, const Color(0xFF5B7FD4));
    });
    test('warn is butter yellow', () {
      expect(AppColors.fkWarn, const Color(0xFFFFC857));
    });
    test('danger is coral', () {
      expect(AppColors.fkDanger, const Color(0xFFE76F51));
    });
    test('surface is warm cream', () {
      expect(AppColors.surface, const Color(0xFFFBF8F3));
    });
    test('on-surface is plum-ink', () {
      expect(AppColors.onSurface, const Color(0xFF2D2438));
    });
  });
}
