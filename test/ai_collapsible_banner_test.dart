import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/ai_collapsible_banner.dart';

void main() {
  Widget _harness({bool initiallyExpanded = false}) {
    return MaterialApp(
      home: Scaffold(
        body: AiCollapsibleBanner(
          urlController: TextEditingController(),
          onParse: () {},
          initiallyExpanded: initiallyExpanded,
        ),
      ),
    );
  }

  testWidgets('starts collapsed and shows hint text', (tester) async {
    await tester.pumpWidget(_harness());
    expect(find.text('✨ 粘贴链接，AI 自动填表'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping the hint expands to reveal url input', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('解析为草稿'), findsOneWidget);
  });

  testWidgets('initiallyExpanded=true shows input from start', (tester) async {
    await tester.pumpWidget(_harness(initiallyExpanded: true));
    expect(find.byType(TextField), findsOneWidget);
  });
}
