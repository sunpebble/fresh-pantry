// test/add_ingredient_quick_entry_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/screens/intake_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('three quick-entry buttons render', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
      ],
      child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
    ));
    expect(find.byKey(const Key('quick_camera')), findsOneWidget);
    expect(find.byKey(const Key('quick_text')), findsOneWidget);
    expect(find.byKey(const Key('quick_manual')), findsOneWidget);
  });

  testWidgets('text quick-entry with N≥2 results pushes review screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AddIngredientScreen(
            textParserOverride: (_) async => [
              IngredientDraft(
                id: 'a',
                name: DraftField.ai('番茄'),
                quantity: DraftField.ai('3'),
                unit: DraftField.ai('个'),
                category: DraftField.ai('蔬菜'),
                storage: DraftField.ai(IconType.fridge),
                shelfLifeDays: DraftField.ai(7),
              ),
              IngredientDraft(
                id: 'b',
                name: DraftField.ai('鸡蛋'),
                quantity: DraftField.ai('6'),
                unit: DraftField.ai('颗'),
                category: DraftField.ai('蛋奶'),
                storage: DraftField.ai(IconType.fridge),
                shelfLifeDays: DraftField.ai(30),
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('quick_text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick_text_input')), '番茄 3 个 鸡蛋 6 颗');
    await tester.tap(find.byKey(const Key('quick_text_parse')));
    await tester.pumpAndSettle();
    expect(find.byType(IntakeReviewScreen), findsOneWidget);
  });
}
