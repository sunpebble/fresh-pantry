import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_skeleton_card.dart';
import 'package:fresh_pantry/widgets/shared/fk_skeleton.dart';

void main() {
  testWidgets('FkRecipeSkeletonCard renders skeleton shapes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: FkRecipeSkeletonCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FkRecipeSkeletonCard), findsOneWidget);
    expect(find.byType(FkSkeletonLine), findsWidgets);
  });
}
