import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/difficulty_stars.dart';

void main() {
  testWidgets('renders 5 star icons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DifficultyStars(value: 3, onChanged: (_) {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
  });

  testWidgets('shows correct label for each value', (tester) async {
    final labels = {1: '简单', 2: '较易', 3: '普通', 4: '进阶', 5: '专业'};
    for (final entry in labels.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DifficultyStars(value: entry.key, onChanged: (_) {}),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget,
          reason: 'value=${entry.key}');
    }
  });

  testWidgets('tapping nth star emits onChanged with n+1', (tester) async {
    final emitted = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DifficultyStars(value: 1, onChanged: emitted.add),
        ),
      ),
    );
    final stars = find.byIcon(Icons.star_rounded);
    await tester.tap(stars.at(2)); // 第 3 颗
    expect(emitted, [3]);
    await tester.tap(stars.at(4)); // 第 5 颗
    expect(emitted, [3, 5]);
  });
}
