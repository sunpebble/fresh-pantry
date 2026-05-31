import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_shimmer.dart';
import 'package:fresh_pantry/widgets/shared/fk_skeleton.dart';

void main() {
  testWidgets('FkShimmer paints child and settles under reduce-motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: FkShimmer(child: FkSkeletonBox(width: 100, height: 20)),
          ),
        ),
      ),
    );
    // reduce-motion: controller does not repeat, pumpAndSettle won't hang.
    await tester.pumpAndSettle();
    expect(find.byType(FkSkeletonBox), findsOneWidget);
  });

  testWidgets('FkSkeletonBox / FkSkeletonLine render with given size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FkSkeletonBox(width: 50, height: 50),
              FkSkeletonLine(width: 120),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(FkSkeletonBox), findsWidgets);
    expect(find.byType(FkSkeletonLine), findsOneWidget);
  });
}
