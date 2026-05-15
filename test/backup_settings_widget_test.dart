import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tap 导出到剪贴板 copies a JSON envelope to clipboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[{"name":"苹果"}]',
    });
    final prefs = await SharedPreferences.getInstance();

    String? capturedClipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        capturedClipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('backup_export_action')),
      200,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup_export_action')));
    await tester.pumpAndSettle();

    expect(capturedClipboard, isNotNull);
    expect(capturedClipboard, contains('"version": 1'));
    expect(capturedClipboard, contains('inventory_items'));
    expect(capturedClipboard, contains('苹果'));
  });

  testWidgets('tap 从剪贴板导入 → confirm overwrites prefs and prompts restart',
      (tester) async {
    final blob = r'''
{
  "version": 1,
  "exportedAt": "2026-05-15T13:00:00.000Z",
  "data": {
    "inventory_items": "[{\"name\":\"导入测试\"}]"
  }
}
''';
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[{"name":"旧"}]',
    });
    final prefs = await SharedPreferences.getInstance();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': blob};
      }
      return null;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('backup_import_action')),
      200,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup_import_action')));
    await tester.pumpAndSettle();

    expect(find.text('确认导入?'), findsOneWidget,
        reason: 'confirm dialog must appear before destructive write');

    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();

    expect(prefs.getString('inventory_items'), '[{"name":"导入测试"}]');
    expect(find.textContaining('请重启 App'), findsOneWidget);
  });
}
