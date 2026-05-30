import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/widgets/shopping/quick_add_field.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('quick add field hides suggestion chips below the input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, shopping: const []),
        ],
        child: const MaterialApp(home: Scaffold(body: QuickAddField())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加食材到清单...'), findsOneWidget);
    expect(find.textContaining('+ '), findsNothing);
  });

  testWidgets('submitting a name appends an item to the shopping provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, shopping: const []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return const QuickAddField();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider), isEmpty);

    await tester.enterText(find.byType(TextField), '番茄');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final items = container.read(shoppingProvider);
    expect(items, hasLength(1));
    expect(items.single.name, '番茄');
    // After submit the field should clear so the next entry starts blank.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });
}
