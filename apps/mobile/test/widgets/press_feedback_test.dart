import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_card.dart';
import 'package:fresh_pantry/widgets/shared/fk_icon_button.dart';
import 'package:fresh_pantry/widgets/shared/fk_pressable.dart';

void main() {
  testWidgets('FkCard with onTap wraps in FkAnimatedPressable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FkCard(onTap: () {}, child: const Text('card')),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(FkCard),
        matching: find.byType(FkAnimatedPressable),
      ),
      findsOneWidget,
    );
  });

  testWidgets('FkCard without onTap has no FkAnimatedPressable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FkCard(child: const Text('card'))),
      ),
    );
    expect(find.byType(FkAnimatedPressable), findsNothing);
  });

  testWidgets('FkIconButton wraps tap target in FkAnimatedPressable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FkIconButton(onTap: () {}, child: const Icon(Icons.add)),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(FkIconButton),
        matching: find.byType(FkAnimatedPressable),
      ),
      findsOneWidget,
    );
  });
}
