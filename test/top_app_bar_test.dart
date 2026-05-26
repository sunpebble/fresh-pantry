import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';

void main() {
  testWidgets('search button activates the search overlay provider', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: TopAppBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();

    expect(container.read(searchActiveProvider), isTrue);
  });
}
