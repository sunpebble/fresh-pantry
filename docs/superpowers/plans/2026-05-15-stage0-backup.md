# Stage 0 — JSON Export/Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a manual backup: serialize all user data to a JSON blob copy-able to the clipboard, and import the same blob back. Self-use only — this whole feature is explicitly throwaway when Stage 4 (backend / family sharing) lands.

**Architecture:** A dumb-pipe `BackupService` reads/writes specific `SharedPreferences` keys as opaque JSON strings — it does not decode model shapes, so it can't be invalidated by future field additions. Settings screen grows a "数据备份" FK section with two actions: 导出到剪贴板 / 从剪贴板导入. Import shows a confirm dialog and a "重启 App" prompt after writing prefs (we don't invalidate Riverpod state live — simpler, less risk of partially-loaded state).

**Tech Stack:** Flutter (existing), `dart:convert` for JSON, `flutter/services` `Clipboard` (zero new deps), Riverpod (existing).

**Non-negotiables:**
- No new pub deps. Clipboard is `flutter/services` and is already wired.
- Cache keys (`food_details_cache`, `recipe_details_cache`) are NOT backed up — they regenerate, and including them would bloat the blob.
- Import is destructive: it overwrites all user data and requires a confirm dialog.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/services/backup_service.dart` | Read/write 5 user-data prefs keys as opaque JSON blobs; encode/decode the wrapper with version + timestamp. |
| `lib/screens/settings_screen.dart` (modify) | Add `数据备份` FK section + two action rows. |
| `test/backup_service_test.dart` | Unit tests: round-trip, version check, missing-key tolerance, malformed JSON. |
| `test/backup_settings_widget_test.dart` | Widget test: section visible, buttons wire to clipboard, confirm dialog appears. |

User-data keys backed up (string constants live in their providers):
- `inventory_items` — `lib/providers/inventory_provider.dart:17`
- `add_history` — `lib/providers/inventory_provider.dart:18`
- `shopping_items` — `lib/providers/shopping_provider.dart:14`
- `custom_recipes` — `lib/providers/custom_recipe_provider.dart:10`
- `ai_settings_v1` — `lib/providers/ai_settings_provider.dart:9`

Keys explicitly skipped (regenerable):
- `food_details_cache`, `recipe_details_cache`

Backup envelope JSON shape:

```json
{
  "version": 1,
  "exportedAt": "2026-05-15T13:00:00.000Z",
  "data": {
    "inventory_items": "<original JSON string from prefs>",
    "shopping_items": "<original JSON string from prefs>",
    "add_history": "<original JSON string from prefs>",
    "custom_recipes": "<original JSON string from prefs>",
    "ai_settings_v1": "<original JSON string from prefs>"
  }
}
```

Keys absent from prefs at export time are omitted from `data` (not stored as null). On import, only keys present in `data` are written.

---

## Task 1: BackupService skeleton + unit tests for export shape

**Files:**
- Create: `lib/services/backup_service.dart`
- Create: `test/backup_service_test.dart`

- [ ] **Step 1: Write the failing tests for `exportToMap`**

```dart
// test/backup_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackupService.exportToMap', () {
    test('returns version 1 + exportedAt ISO8601 + data object', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"苹果"}]',
        'shopping_items': '[]',
      });
      final prefs = await SharedPreferences.getInstance();

      final map = BackupService.exportToMap(prefs);

      expect(map['version'], 1);
      expect(map['exportedAt'], isA<String>());
      expect(DateTime.tryParse(map['exportedAt'] as String), isNotNull);
      expect(map['data'], isA<Map<String, dynamic>>());
    });

    test('includes only present user-data keys in data', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"苹果"}]',
        'shopping_items': '[]',
        // 'add_history' absent
        'food_details_cache': '{"should":"be skipped"}',
      });
      final prefs = await SharedPreferences.getInstance();

      final map = BackupService.exportToMap(prefs);
      final data = map['data'] as Map<String, dynamic>;

      expect(data['inventory_items'], '[{"name":"苹果"}]');
      expect(data['shopping_items'], '[]');
      expect(data.containsKey('add_history'), isFalse);
      expect(data.containsKey('food_details_cache'), isFalse,
          reason: 'cache keys must not be backed up');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/backup_service_test.dart`
Expected: FAIL with "Undefined name 'BackupService'".

- [ ] **Step 3: Implement `BackupService.exportToMap`**

```dart
// lib/services/backup_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  BackupService._();

  static const int backupVersion = 1;

  /// User-data SharedPreferences keys that are included in backups.
  /// Cache keys (`food_details_cache`, `recipe_details_cache`) are intentionally
  /// excluded — they regenerate and would bloat the blob.
  static const List<String> userDataKeys = [
    'inventory_items',
    'add_history',
    'shopping_items',
    'custom_recipes',
    'ai_settings_v1',
  ];

  static Map<String, dynamic> exportToMap(SharedPreferences prefs) {
    final data = <String, dynamic>{};
    for (final key in userDataKeys) {
      final value = prefs.getString(key);
      if (value != null) data[key] = value;
    }
    return {
      'version': backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/backup_service_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup_service.dart test/backup_service_test.dart
git commit -m "feat(backup): add BackupService.exportToMap with user-data keys allowlist"
```

---

## Task 2: BackupService — JSON encode + decode with version check

**Files:**
- Modify: `lib/services/backup_service.dart`
- Modify: `test/backup_service_test.dart`

- [ ] **Step 1: Add failing tests for encode/decode**

Append to `test/backup_service_test.dart` (inside `void main()`):

```dart
  group('BackupService.encodeToJson / decodeFromJson', () {
    test('round-trips a map back to the same shape', () {
      final original = {
        'version': 1,
        'exportedAt': '2026-05-15T13:00:00.000Z',
        'data': {
          'inventory_items': '[{"name":"苹果"}]',
        },
      };

      final json = BackupService.encodeToJson(original);
      final decoded = BackupService.decodeFromJson(json);

      expect(decoded, original);
    });

    test('encodeToJson produces pretty-printed (indent 2) output', () {
      final json = BackupService.encodeToJson({'version': 1, 'data': {}});
      expect(json, contains('\n  '));
    });

    test('decodeFromJson throws on malformed JSON', () {
      expect(
        () => BackupService.decodeFromJson('{not valid'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodeFromJson throws on unsupported version', () {
      final json = BackupService.encodeToJson({'version': 99, 'data': {}});
      expect(
        () => BackupService.decodeFromJson(json),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('decodeFromJson throws when version is missing', () {
      expect(
        () => BackupService.decodeFromJson('{"data":{}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/backup_service_test.dart`
Expected: FAIL with "Undefined name 'encodeToJson'" etc.

- [ ] **Step 3: Implement encode + decode + version exception**

Add to `lib/services/backup_service.dart`:

```dart
import 'dart:convert';

class BackupVersionException implements Exception {
  BackupVersionException(this.message);
  final String message;
  @override
  String toString() => 'BackupVersionException: $message';
}

// Inside class BackupService:
  static String encodeToJson(Map<String, dynamic> map) {
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static Map<String, dynamic> decodeFromJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup blob is not a JSON object');
    }
    final version = decoded['version'];
    if (version is! int) {
      throw BackupVersionException(
        'Missing or invalid version (got: $version)',
      );
    }
    if (version != backupVersion) {
      throw BackupVersionException(
        'Unsupported backup version $version (expected $backupVersion)',
      );
    }
    return decoded;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/backup_service_test.dart`
Expected: PASS (5 new tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup_service.dart test/backup_service_test.dart
git commit -m "feat(backup): add JSON encode/decode with version check"
```

---

## Task 3: BackupService — write back to prefs (importFromMap)

**Files:**
- Modify: `lib/services/backup_service.dart`
- Modify: `test/backup_service_test.dart`

- [ ] **Step 1: Add failing tests for `importFromMap`**

Append to `test/backup_service_test.dart`:

```dart
  group('BackupService.importFromMap', () {
    test('writes each present user-data key back to prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'exportedAt': '2026-05-15T13:00:00.000Z',
        'data': {
          'inventory_items': '[{"name":"苹果"}]',
          'shopping_items': '[]',
        },
      });

      expect(prefs.getString('inventory_items'), '[{"name":"苹果"}]');
      expect(prefs.getString('shopping_items'), '[]');
      expect(prefs.getString('add_history'), isNull);
    });

    test('ignores keys outside the userDataKeys allowlist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'data': {
          'inventory_items': '[]',
          'food_details_cache': '"malicious"',
          'unknown_key': '"hostile"',
        },
      });

      expect(prefs.getString('inventory_items'), '[]');
      expect(prefs.getString('food_details_cache'), isNull,
          reason: 'cache keys must not be importable');
      expect(prefs.getString('unknown_key'), isNull);
    });

    test('overwrites existing values', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"old":true}]',
      });
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'data': {'inventory_items': '[{"new":true}]'},
      });

      expect(prefs.getString('inventory_items'), '[{"new":true}]');
    });

    test('round-trips: export → encode → decode → import → same prefs', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"葱"}]',
        'shopping_items': '[{"id":"si_1"}]',
        'add_history': '{"葱":{"count":3}}',
      });
      final source = await SharedPreferences.getInstance();
      final exported = BackupService.exportToMap(source);
      final json = BackupService.encodeToJson(exported);

      SharedPreferences.setMockInitialValues({});
      final target = await SharedPreferences.getInstance();
      final decoded = BackupService.decodeFromJson(json);
      await BackupService.importFromMap(target, decoded);

      expect(target.getString('inventory_items'), '[{"name":"葱"}]');
      expect(target.getString('shopping_items'), '[{"id":"si_1"}]');
      expect(target.getString('add_history'), '{"葱":{"count":3}}');
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/backup_service_test.dart`
Expected: FAIL with "Undefined name 'importFromMap'".

- [ ] **Step 3: Implement `importFromMap`**

Add inside class `BackupService`:

```dart
  static Future<void> importFromMap(
    SharedPreferences prefs,
    Map<String, dynamic> envelope,
  ) async {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Backup data is not a JSON object');
    }
    for (final key in userDataKeys) {
      final value = data[key];
      if (value is String) {
        await prefs.setString(key, value);
      }
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/backup_service_test.dart`
Expected: PASS (all groups: 4 round-trip + import tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup_service.dart test/backup_service_test.dart
git commit -m "feat(backup): add importFromMap with allowlist filtering"
```

---

## Task 4: Settings screen — add 数据备份 FK section (UI only)

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Inspect existing section pattern**

Read `lib/screens/settings_screen.dart` lines 69-100 to see how 临期提醒 section is composed: `FkSectionHead` + `Padding(horizontal: 18, child: FkCard(...))` with `_ToggleRow` children.

- [ ] **Step 2: Add a new `_ActionRow` widget inside the file**

Add at the bottom of `settings_screen.dart` (next to `_ToggleRow`):

```dart
/// A tappable settings row: leading icon (optional) + label + trailing chevron.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    this.sub,
    required this.onTap,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final String? sub;
  final VoidCallback onTap;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.fkDanger : AppColors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Insert 数据备份 section in `build`**

Inside `ListView`'s `children` (in `_SettingsScreenState.build`), find the existing 临期提醒 section and insert this block immediately after it (before any 饮食偏好 or 更多 section if present):

```dart
            const FkSectionHead(title: '数据备份'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: FkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionRow(
                      key: const Key('backup_export_action'),
                      label: '导出到剪贴板',
                      sub: '复制全部数据为 JSON,粘贴到 Notes/邮箱保存',
                      icon: Icons.upload_outlined,
                      onTap: _onExportTap,
                    ),
                    const Divider(height: 1, color: AppColors.hair),
                    _ActionRow(
                      key: const Key('backup_import_action'),
                      label: '从剪贴板导入',
                      sub: '会覆盖当前所有数据',
                      icon: Icons.download_outlined,
                      destructive: true,
                      onTap: _onImportTap,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
```

- [ ] **Step 4: Add stub handlers**

Inside `_SettingsScreenState`, add:

```dart
  void _onExportTap() {
    // Wired in Task 5.
  }

  void _onImportTap() {
    // Wired in Task 6.
  }
```

- [ ] **Step 5: `flutter analyze` + commit**

Run: `flutter analyze`
Expected: 0 errors.

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(settings): add 数据备份 section UI (handlers stubbed)"
```

---

## Task 5: Wire export action — copy to clipboard

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Create: `test/backup_settings_widget_test.dart`

- [ ] **Step 1: Write the failing widget test for export**

```dart
// test/backup_settings_widget_test.dart
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

    await tester.tap(find.byKey(const Key('backup_export_action')));
    await tester.pumpAndSettle();

    expect(capturedClipboard, isNotNull);
    expect(capturedClipboard, contains('"version": 1'));
    expect(capturedClipboard, contains('inventory_items'));
    expect(capturedClipboard, contains('苹果'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/backup_settings_widget_test.dart`
Expected: FAIL (`capturedClipboard` is null because export handler is stub).

- [ ] **Step 3: Implement export handler**

Add imports to `lib/screens/settings_screen.dart`:

```dart
import 'package:flutter/services.dart';
import '../services/backup_service.dart';
import '../utils/fk_toast.dart';
```

(If `fk_toast` does not exist with `fkToast(context, msg)` signature, instead use `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))` inline — pick whichever your codebase already has.)

Replace `_onExportTap` with:

```dart
  Future<void> _onExportTap() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final envelope = BackupService.exportToMap(prefs);
    final json = BackupService.encodeToJson(envelope);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    final bytes = json.length;
    fkToast(context, '已复制 $bytes 字节,粘贴到 Notes/邮箱保存');
  }
```

If `fkToast` is unavailable, substitute:

```dart
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 $bytes 字节,粘贴到 Notes/邮箱保存')),
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/backup_settings_widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart test/backup_settings_widget_test.dart
git commit -m "feat(settings): wire 数据备份 export to clipboard"
```

---

## Task 6: Wire import action — read clipboard, confirm, write back

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `test/backup_settings_widget_test.dart`

- [ ] **Step 1: Write the failing widget test for import**

Append to `test/backup_settings_widget_test.dart`:

```dart
  testWidgets('tap 从剪贴板导入 → confirm overwrites prefs and prompts restart',
      (tester) async {
    final blob = '''
{
  "version": 1,
  "exportedAt": "2026-05-15T13:00:00.000Z",
  "data": {
    "inventory_items": "[{\\\"name\\\":\\\"导入测试\\\"}]"
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

    await tester.tap(find.byKey(const Key('backup_import_action')));
    await tester.pumpAndSettle();

    expect(find.text('确认导入?'), findsOneWidget,
        reason: 'confirm dialog must appear before destructive write');

    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();

    expect(prefs.getString('inventory_items'), '[{"name":"导入测试"}]');
    expect(find.textContaining('请重启 App'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/backup_settings_widget_test.dart`
Expected: FAIL (confirm dialog never appears, prefs unchanged).

- [ ] **Step 3: Implement import handler**

Replace `_onImportTap` in `_SettingsScreenState`:

```dart
  Future<void> _onImportTap() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      _showSimpleDialog('剪贴板为空', '请先在另一台设备复制备份 JSON 后再试。');
      return;
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = BackupService.decodeFromJson(text);
    } on BackupVersionException catch (e) {
      _showSimpleDialog('备份版本不兼容', e.message);
      return;
    } on FormatException catch (e) {
      _showSimpleDialog('备份不是合法 JSON', e.message);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入?'),
        content: const Text('将覆盖当前的所有食材、购物清单、菜谱与 AI 设置。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.fkDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认覆盖'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = ref.read(sharedPreferencesProvider);
    await BackupService.importFromMap(prefs, decoded);
    if (!mounted) return;
    _showSimpleDialog('导入完成', '请重启 App 以加载新数据。');
  }

  Future<void> _showSimpleDialog(String title, String body) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/backup_settings_widget_test.dart`
Expected: PASS (both export and import widget tests).

- [ ] **Step 5: Manual smoke**

```bash
flutter run -d ios
```

In Settings → 数据备份:
- Tap 导出到剪贴板 → expect toast/snackbar with "已复制 N 字节"
- Open Notes app, paste — confirm JSON looks like envelope shape
- Edit one row in inventory; tap 从剪贴板导入 → confirm dialog → 确认覆盖 → "请重启 App" dialog
- Kill + relaunch app → expect the imported state (the edit you made is gone)

- [ ] **Step 6: Commit**

```bash
git add lib/screens/settings_screen.dart test/backup_settings_widget_test.dart
git commit -m "feat(settings): wire 数据备份 import with confirm dialog + restart prompt"
```

---

## Task 7: Final analyze + push

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: PASS (all existing + new tests).

- [ ] **Step 2: `flutter analyze`**

Expected: 0 errors. Warnings about unused private fields/imports are acceptable only if they pre-date this branch.

- [ ] **Step 3: Push branch**

```bash
git push -u origin HEAD
```

---

## Self-Review

**Spec coverage:**
- ✅ Serialize 5 user-data prefs keys (Task 1) — checked against keys listed in plan header
- ✅ Skip cache keys (Task 1 + 3) — tested
- ✅ Version envelope + version-mismatch error (Task 2)
- ✅ Round-trip preserved (Task 3)
- ✅ Settings UI section (Task 4)
- ✅ Export to clipboard with toast (Task 5)
- ✅ Import with confirm dialog + restart prompt (Task 6)
- ✅ Zero new pub deps (uses `flutter/services` Clipboard + existing `shared_preferences`)

**Placeholder scan:** No TBD / TODO / "fill in" — every step has runnable code.

**Type consistency:** `BackupService.exportToMap` / `importFromMap` / `encodeToJson` / `decodeFromJson` / `userDataKeys` / `backupVersion` / `BackupVersionException` are consistent across Tasks 1-3 and Tasks 5-6.

**Risk register:**
- Risk: `fkToast` may not exist in current codebase. **Mitigation**: Task 5 Step 3 gives a fallback to `ScaffoldMessenger.showSnackBar`. Subagent: check before substituting.
- Risk: very large clipboard payload (e.g. AI recipe details cache if accidentally included). **Mitigation**: cache keys are explicitly excluded via `userDataKeys` allowlist (test covered).
- Risk: clipboard read returns stale data. **Mitigation**: user-driven action, single-shot; not a flow that re-reads.
