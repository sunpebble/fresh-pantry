import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_shadows.dart';
import 'package:fresh_pantry/theme/app_colors.dart';

void main() {
  test('card shadow has two layers using shadowSoft', () {
    expect(AppShadows.card.length, 2);
    expect(AppShadows.card.first.color, AppColors.shadowSoft);
    expect(AppShadows.card[1].blurRadius, 16);
  });

  test('soft and strong shadows are defined', () {
    expect(AppShadows.soft.length, 1);
    expect(AppShadows.soft.first.blurRadius, 12);
    expect(AppShadows.strong.first.color, AppColors.shadowWarm);
    expect(AppShadows.strong.first.blurRadius, 18);
  });
}
