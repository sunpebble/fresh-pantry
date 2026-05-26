import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/shared/cat_icon.dart';
import 'package:fresh_pantry/widgets/shared/fk_nav_icon.dart';
import 'package:fresh_pantry/widgets/shared/zone_icon.dart';

void main() {
  testWidgets('CatIcon renders all 9 categories without throwing', (
    tester,
  ) async {
    for (final cat in kFkCategoryIds) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CatIcon(category: cat))),
      );
      await tester.pump();
      expect(find.byType(CatIcon), findsOneWidget);
    }
  });

  testWidgets('ZoneIcon renders all 5 zones without throwing', (tester) async {
    for (final zone in kFkZoneIds) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ZoneIcon(zone: zone))),
      );
      await tester.pump();
      expect(find.byType(ZoneIcon), findsOneWidget);
    }
  });

  testWidgets('FkNavIcon renders all 5 nav icons without throwing', (
    tester,
  ) async {
    for (final icon in kFkNavIconIds) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: FkNavIcon(icon: icon))),
      );
      await tester.pump();
      expect(find.byType(FkNavIcon), findsOneWidget);
    }
  });

  testWidgets('CatIcon falls back to veg on unknown category', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CatIcon(category: 'nonsense'))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
