import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/unit_dropdown.dart';

void main() {
  Widget _harness({String value = '', ValueChanged<String>? onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: UnitDropdown(value: value, onChanged: onChanged ?? (_) {}),
      ),
    );
  }

  testWidgets('shows current value with caret', (tester) async {
    await tester.pumpWidget(_harness(value: 'g'));
    expect(find.textContaining('g'), findsOneWidget);
  });

  testWidgets('shows placeholder when value is empty', (tester) async {
    await tester.pumpWidget(_harness(value: ''));
    expect(find.textContaining('单位'), findsOneWidget);
  });

  testWidgets('tapping opens bottom sheet with preset units', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.byType(UnitDropdown));
    await tester.pumpAndSettle();

    expect(find.text('g'), findsOneWidget);
    expect(find.text('个'), findsOneWidget);
    expect(find.text('适量'), findsOneWidget);
    expect(find.text('自定义…'), findsOneWidget);
  });

  testWidgets('selecting a unit closes sheet and emits onChanged',
      (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(_harness(onChanged: emitted.add));
    await tester.tap(find.byType(UnitDropdown));
    await tester.pumpAndSettle();

    await tester.tap(find.text('个'));
    await tester.pumpAndSettle();

    expect(emitted, ['个']);
  });
}
