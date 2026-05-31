import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_entrance.dart';

void main() {
  testWidgets('renders child immediately (final opacity reached)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FkEntrance(index: 0, child: Text('hello'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 1.0);
  });

  testWidgets('reduce-motion shows child at full opacity immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: FkEntrance(index: 3, child: Text('x'))),
        ),
      ),
    );
    // reduce-motion: immediate final state, no settle needed.
    expect(find.text('x'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('x'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 1.0);
  });
}
