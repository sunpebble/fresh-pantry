import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/common/swipe_reveal_delete_action.dart';

void main() {
  testWidgets('reveals delete action and invokes callback after a left swipe', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
          body: SwipeRevealDeleteAction(
            deleteButtonKey: const Key('delete_action'),
            onDelete: () => deleted = true,
            child: const SizedBox(height: 72, child: Center(child: Text('苹果'))),
          ),
        ),
      ),
    );

    await tester.drag(find.text('苹果'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_action')));

    expect(deleted, isTrue);
  });
}
