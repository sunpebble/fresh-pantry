import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ai_settings_screen.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings icon pushes AiSettingsScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: TopAppBar())),
    ));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AiSettingsScreen), findsOneWidget);
  });
}
