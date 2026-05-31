import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_motion.dart';

void main() {
  test('durations follow the restrained-premium ladder', () {
    expect(AppDuration.fast.inMilliseconds, 120);
    expect(AppDuration.normal.inMilliseconds, 180);
    expect(AppDuration.slow.inMilliseconds, 250);
    expect(AppDuration.page.inMilliseconds, 240);
    expect(AppDuration.shimmer.inMilliseconds, 1400);
  });

  test('curves and motion params are defined', () {
    expect(AppMotionCurves.standard, Curves.easeOutCubic);
    expect(AppMotion.pressScale, 0.97);
    expect(AppMotion.entranceOffset, 8);
    expect(AppMotion.staggerStep.inMilliseconds, 50);
  });
}
