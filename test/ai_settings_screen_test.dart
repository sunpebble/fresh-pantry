import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/ai_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ai_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _harness({Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MaterialApp(home: AiSettingsScreen()),
  );
}

void main() {
  testWidgets('shows three required text fields and timeout', (tester) async {
    await tester.pumpWidget(await _harness());
    expect(find.byKey(const Key('ai_base_url')), findsOneWidget);
    expect(find.byKey(const Key('ai_api_key')), findsOneWidget);
    expect(find.byKey(const Key('ai_model')), findsOneWidget);
    expect(find.byKey(const Key('ai_timeout')), findsOneWidget);
  });

  testWidgets('save button persists to provider', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AiSettingsScreen()),
    ));

    await tester.enterText(find.byKey(const Key('ai_base_url')), 'https://api.example.com/v1');
    await tester.enterText(find.byKey(const Key('ai_api_key')), 'sk-x');
    await tester.enterText(find.byKey(const Key('ai_model')), 'gpt-4o');
    await tester.tap(find.byKey(const Key('ai_save')));
    await tester.pumpAndSettle();

    final saved = container.read(aiSettingsProvider);
    expect(saved.baseUrl, 'https://api.example.com/v1');
    expect(saved.apiKey, 'sk-x');
    expect(saved.model, 'gpt-4o');
  });

  testWidgets('test connection shows result via injected callback', (tester) async {
    var called = false;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: AiSettingsScreen(
          testConnection: (_) async {
            called = true;
            return const ConnectionTestResult.ok();
          },
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('ai_base_url')), 'https://x/v1');
    await tester.enterText(find.byKey(const Key('ai_api_key')), 'sk');
    await tester.enterText(find.byKey(const Key('ai_model')), 'm');
    await tester.tap(find.byKey(const Key('ai_test_connection')));
    await tester.pumpAndSettle();

    expect(called, true);
    expect(find.text('连接成功'), findsOneWidget);
  });
}
