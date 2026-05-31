import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FkAnimatedPressable(
            onTap: () => tapped = true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FkAnimatedPressable));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('scales down on tap-down then restores', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FkAnimatedPressable(
              onTap: () {},
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    AnimatedScale scaleOf() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scaleOf().scale, 1.0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FkAnimatedPressable)),
    );
    await tester.pump();
    expect(scaleOf().scale, lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf().scale, 1.0);
  });

  testWidgets('reduce-motion disables the scale animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: FkAnimatedPressable(
                onTap: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );
    // reduce-motion 下不渲染 AnimatedScale,仅保留点击。
    expect(find.byType(AnimatedScale), findsNothing);
  });

  testWidgets('emits a haptic on tap-down without throwing', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FkAnimatedPressable(
            onTap: () {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FkAnimatedPressable));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'HapticFeedback.vibrate'), isTrue);
  });
}
