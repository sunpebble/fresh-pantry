import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/page_transitions.dart';
import 'package:fresh_pantry/theme/app_motion.dart';

void main() {
  testWidgets('fkRoute pushes and reveals the destination', (tester) async {
    final route = fkRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, AppDuration.page);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(fkRoute<void>(builder: (_) => const _DestPage())),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(_DestPage), findsOneWidget);
  });

  test('fkRoute uses the page duration token', () {
    final route = fkRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, AppDuration.page);
  });
}

class _DestPage extends StatelessWidget {
  const _DestPage();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('dest'));
}
