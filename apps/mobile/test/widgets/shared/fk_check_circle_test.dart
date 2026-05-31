import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/fk_check_circle.dart';

void main() {
  testWidgets('toggles and reports tap', (tester) async {
    var checked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: FkCheckCircle(
                checked: checked,
                onTap: () => setState(() => checked = !checked),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.byType(FkCheckCircle));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
