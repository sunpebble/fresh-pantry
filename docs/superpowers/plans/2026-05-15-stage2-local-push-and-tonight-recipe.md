# Stage 2 — Local Push + 今晚做啥 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use `- [ ]` syntax.
>
> **Reference docs:**
> - Roadmap memory: `memory/stage_roadmap_2026_05.md` (Stage 2 = local push + decision hook; depends on Stage 1)
> - Self-use mode: `memory/project_mode_self_use.md`
> - Glossary: `CONTEXT.md` (Urgency Status: fresh / soon / urgent / expired / low-stock)

**Goal:** Unattended expiry awareness + a single "今晚做啥" decision hook. After this stage, the user can keep ingredients on track without opening the App every day, and when they do open it, the Dashboard shows one concrete recipe suggestion that prioritises expiring stock.

**Architecture:**
- `NotificationService` wraps `flutter_local_notifications` — handles init, permission, schedule, cancel. Single source of truth for OS notification calls.
- `ReminderSettings` model + `reminderSettingsProvider` persist the 4 existing toggles (D1 / D3 / D7 / Daily) to `reminder_settings_v1` prefs key, replacing the local-only state in `SettingsScreen`.
- `ExpiryScheduler` is a pure function: given current `inventory` + `ReminderSettings`, returns the list of `ScheduledNotification` records (deterministic IDs derived from ingredient + offset).
- `notificationSyncProvider` listens to `inventoryProvider` and `reminderSettingsProvider`, diffs against currently-scheduled, and calls `NotificationService.scheduleAll(diff)` — so any inventory mutation or toggle flip eagerly resyncs.
- `recommendedRecipesProvider` (already exists at `lib/providers/recipe_provider.dart:174`) is enhanced: the score multiplier rewards recipes that consume expiring items.

**Tech Stack:** Flutter (existing), Riverpod (existing), SharedPreferences (existing), `flutter_local_notifications` (new dep).

**Non-negotiables:**
- **Local only.** No FCM, no APNs, no remote scheduling. Stage 4 territory.
- **Lazy permission.** Don't ask on first launch. Ask the first time the user flips a reminder toggle ON.
- **9 AM local time.** All scheduled notifications fire at 09:00 in the user's local timezone. No per-user time pickers in this stage (deferred).
- **Daily summary only fires when there's something to say.** If 0 items expire today AND 0 are already expired, skip the 9am summary that day.
- **Deterministic notification IDs.** Hash of `ingredient.name + storage + addedAt.millisecondsSinceEpoch + offsetDays` so we can cancel/reschedule without orphan notifications.
- **No background fetch.** Scheduling is event-driven (inventory or settings changes). Daily summary is a recurring `zonedSchedule` that the OS handles.
- **iOS + Android both supported** via `flutter_local_notifications` — no platform-specific code beyond the iOS Info.plist permission flag and the Android `AndroidManifest.xml` post-N permission.

**Out of scope:**
- Per-user notification time customisation (locked to 9am).
- Snooze / dismiss actions (only `tap → open app`).
- Notification action buttons (e.g. "标记已用").
- Push for low-stock or shopping list reminders (the 4 toggles cover expiry only).
- Telemetry / observability for delivery rates.

---

## File Structure

| File | Responsibility | Phase |
|---|---|---|
| `pubspec.yaml` (modify) | + `flutter_local_notifications`, `timezone` deps | 1 |
| `ios/Runner/Info.plist` (modify) | Notification permission strings | 1 |
| `android/app/src/main/AndroidManifest.xml` (modify) | `POST_NOTIFICATIONS` permission for Android 13+ | 1 |
| `lib/services/notification_service.dart` (create) | Wraps `flutter_local_notifications`; init / permission / schedule / cancel | 1 |
| `lib/models/reminder_settings.dart` (create) | Immutable data class with 4 booleans + toJson/fromJson | 2 |
| `lib/providers/reminder_settings_provider.dart` (create) | `Notifier<ReminderSettings>` with prefs persistence | 2 |
| `lib/screens/settings_screen.dart` (modify) | Wire 4 toggles to provider; show "通知权限未开启" banner when denied | 2, 4 |
| `lib/models/scheduled_notification.dart` (create) | Plain data: `id`, `ingredientName`, `scheduledAt`, `body` | 3 |
| `lib/services/expiry_scheduler.dart` (create) | Pure function `compute(inventory, settings, now) -> List<ScheduledNotification>` | 3 |
| `lib/providers/notification_sync_provider.dart` (create) | Listens to inventory + settings, computes diff, calls service | 3 |
| `lib/main.dart` (modify) | Init NotificationService at bootstrap; wire tap handler | 1, 6 |
| `lib/providers/recipe_provider.dart` (modify) | Enhance scoring to boost recipes using expiring items | 5 |
| `lib/screens/dashboard_screen.dart` (modify) | Existing "今日推荐" card uses the enhanced ranking (no UI change) | 5 |
| Tests under `test/` (create) | Per-task unit + provider tests | all |

---

## Phase 1: Foundation — deps + NotificationService skeleton

### Task 1.1: Add deps + iOS / Android permission strings

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add to `pubspec.yaml` dependencies**

Add under existing deps, alphabetised:

```yaml
  flutter_local_notifications: ^18.0.1
  timezone: ^0.9.4
```

- [ ] **Step 2: Run `flutter pub get`**

Expected: deps resolved, `pubspec.lock` regenerated.

- [ ] **Step 3: Add iOS `Info.plist` keys**

Open `ios/Runner/Info.plist` and add inside `<dict>...</dict>`:

```xml
	<key>UNUserNotificationCenterDelegateClass</key>
	<string></string>
```

(Empty value is fine — the plugin's example uses this pattern. If a similar key already exists, leave as-is.)

> NOTE: iOS notification permission is requested at runtime via the plugin; no plist-level rationale string is required for local-only notifications.

- [ ] **Step 4: Add Android post-13 permission**

Edit `android/app/src/main/AndroidManifest.xml`, inside the `<manifest>` element (not `<application>`):

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

If these already exist, leave as-is.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
git commit -m "chore(notifications): add flutter_local_notifications + timezone deps"
```

---

### Task 1.2: NotificationService skeleton

**Files:**
- Create: `lib/services/notification_service.dart`
- Create: `test/notification_service_test.dart`

- [ ] **Step 1: Write failing test for permission flag**

```dart
// test/notification_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/notification_service.dart';

void main() {
  test('NotificationService starts uninitialized', () {
    final svc = NotificationService();
    expect(svc.isInitialized, isFalse);
    expect(svc.permissionGranted, isFalse);
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement skeleton**

```dart
// lib/services/notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/scheduled_notification.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _permissionGranted = false;

  bool get isInitialized => _initialized;
  bool get permissionGranted => _permissionGranted;

  Future<void> init({void Function(int notificationId)? onTap}) async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final id = resp.id;
        if (id != null) onTap?.call(id);
      },
    );
    _initialized = true;
  }

  /// Asks the OS for permission. Returns whether permission is granted after
  /// the call. Should be invoked only after [init].
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    final ios = await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final android = await androidImpl?.requestNotificationsPermission();

    _permissionGranted = (ios ?? android ?? false);
    return _permissionGranted;
  }

  /// Schedules a single notification at the given local DateTime.
  Future<void> schedule(ScheduledNotification n) async {
    if (!_initialized || !_permissionGranted) return;
    final scheduledTz = tz.TZDateTime.from(n.scheduledAt, tz.local);
    if (scheduledTz.isBefore(tz.TZDateTime.now(tz.local))) return; // past
    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      scheduledTz,
      _notifDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedules a list — cancels existing IDs first, then writes the new set.
  Future<void> syncAll(
    List<ScheduledNotification> next, {
    required List<int> previousIds,
  }) async {
    if (!_initialized || !_permissionGranted) return;
    for (final id in previousIds) {
      await _plugin.cancel(id);
    }
    for (final n in next) {
      await schedule(n);
    }
  }

  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
  }

  NotificationDetails _notifDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'fresh_pantry_expiry',
          '临期提醒',
          channelDescription: '食材临期 / 过期推送',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  @visibleForTesting
  void debugSetState({required bool initialized, required bool permission}) {
    _initialized = initialized;
    _permissionGranted = permission;
  }
}
```

- [ ] **Step 4: Run test** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/notification_service.dart test/notification_service_test.dart
git commit -m "feat(notifications): NotificationService skeleton (init / permission / schedule)"
```

> NOTE: `ScheduledNotification` is created in Task 3.1 — this commit will not compile until 3.1 lands. If `flutter analyze` complains, temporarily inline a `ScheduledNotification` placeholder in this file with the same fields (`id`, `title`, `body`, `scheduledAt`), and remove it when 3.1 lands. Easier: re-order so Task 3.1 happens first inside Phase 1. **Decision: reorder — do Task 3.1 as Task 1.3 below, before this Task 1.2 fully compiles.**

> ACTION FOR IMPLEMENTER: implement Task 1.3 (ScheduledNotification model) before this task's flutter analyze step, OR temporarily inline the model in this file with a TODO to migrate. Either way: the file structure converges after 1.3.

---

### Task 1.3: `ScheduledNotification` data type

**Files:**
- Create: `lib/models/scheduled_notification.dart`

- [ ] **Step 1: Implement**

```dart
// lib/models/scheduled_notification.dart
import 'package:flutter/foundation.dart';

@immutable
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    this.kind = ScheduledNotificationKind.expiry,
  });

  final int id;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final ScheduledNotificationKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledNotification &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          scheduledAt == other.scheduledAt &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(id, title, body, scheduledAt, kind);
}

enum ScheduledNotificationKind { expiry, dailySummary }
```

- [ ] **Step 2: Commit**

```bash
git add lib/models/scheduled_notification.dart
git commit -m "feat(notifications): ScheduledNotification data type"
```

---

### Task 1.4: Bootstrap NotificationService in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add provider override + init**

In `lib/main.dart`, find the `main()` function. After `WidgetsFlutterBinding.ensureInitialized()` and before `runApp(...)`, add:

```dart
final notificationService = NotificationService();
await notificationService.init();
```

Add a provider in `lib/providers/notification_service_provider.dart` (new file):

```dart
// lib/providers/notification_service_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider must be overridden in main.dart',
  ),
);
```

Wire override into `ProviderScope`:

```dart
runApp(
  ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notificationService),
      // ... existing overrides
    ],
    child: const FreshPantryApp(),
  ),
);
```

- [ ] **Step 2: `flutter analyze` 0 errors**

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart lib/providers/notification_service_provider.dart
git commit -m "feat(notifications): bootstrap NotificationService in main"
```

---

## Phase 2: Reminder Settings persistence

### Task 2.1: ReminderSettings model + tests

**Files:**
- Create: `lib/models/reminder_settings.dart`
- Create: `test/reminder_settings_test.dart`

- [ ] **Step 1: Tests**

```dart
// test/reminder_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';

void main() {
  test('default values match historical local-state defaults', () {
    const s = ReminderSettings();
    expect(s.remindD1, isTrue);
    expect(s.remindD3, isTrue);
    expect(s.remindD7, isFalse);
    expect(s.remindDaily, isTrue);
  });

  test('copyWith preserves other fields', () {
    const s = ReminderSettings();
    final s2 = s.copyWith(remindD7: true);
    expect(s2.remindD7, isTrue);
    expect(s2.remindD1, isTrue);
  });

  test('toJson / fromJson round-trip', () {
    const s = ReminderSettings(remindD1: false, remindD7: true);
    final json = s.toJson();
    final restored = ReminderSettings.fromJson(json);
    expect(restored, s);
  });

  test('fromJson tolerates missing keys (returns default for them)', () {
    final s = ReminderSettings.fromJson({'remindD7': true});
    expect(s.remindD7, isTrue);
    expect(s.remindD1, isTrue, reason: 'missing → default');
  });

  test('enabledOffsetDays returns sorted list of enabled D-offsets', () {
    const s = ReminderSettings(remindD1: true, remindD3: false, remindD7: true);
    expect(s.enabledOffsetDays, [7, 1]);
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/models/reminder_settings.dart
import 'package:flutter/foundation.dart';

@immutable
class ReminderSettings {
  const ReminderSettings({
    this.remindD1 = true,
    this.remindD3 = true,
    this.remindD7 = false,
    this.remindDaily = true,
  });

  final bool remindD1;
  final bool remindD3;
  final bool remindD7;
  final bool remindDaily;

  /// Returns the enabled D-N offsets sorted earliest-first (largest N first).
  /// Used by ExpiryScheduler to know which per-item reminders to schedule.
  List<int> get enabledOffsetDays => [
        if (remindD7) 7,
        if (remindD3) 3,
        if (remindD1) 1,
      ];

  ReminderSettings copyWith({
    bool? remindD1,
    bool? remindD3,
    bool? remindD7,
    bool? remindDaily,
  }) =>
      ReminderSettings(
        remindD1: remindD1 ?? this.remindD1,
        remindD3: remindD3 ?? this.remindD3,
        remindD7: remindD7 ?? this.remindD7,
        remindDaily: remindDaily ?? this.remindDaily,
      );

  Map<String, dynamic> toJson() => {
        'remindD1': remindD1,
        'remindD3': remindD3,
        'remindD7': remindD7,
        'remindDaily': remindDaily,
      };

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        remindD1: j['remindD1'] as bool? ?? true,
        remindD3: j['remindD3'] as bool? ?? true,
        remindD7: j['remindD7'] as bool? ?? false,
        remindDaily: j['remindDaily'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderSettings &&
          remindD1 == other.remindD1 &&
          remindD3 == other.remindD3 &&
          remindD7 == other.remindD7 &&
          remindDaily == other.remindDaily;

  @override
  int get hashCode =>
      Object.hash(remindD1, remindD3, remindD7, remindDaily);
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/reminder_settings.dart test/reminder_settings_test.dart
git commit -m "feat(notifications): ReminderSettings data type"
```

---

### Task 2.2: ReminderSettingsNotifier + persistence

**Files:**
- Create: `lib/providers/reminder_settings_provider.dart`
- Create: `test/reminder_settings_provider_test.dart`

- [ ] **Step 1: Tests**

```dart
// test/reminder_settings_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';
import 'package:fresh_pantry/providers/reminder_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
}

void main() {
  test('reads defaults when prefs empty', () async {
    final c = await _container();
    final s = c.read(reminderSettingsProvider);
    expect(s, const ReminderSettings());
  });

  test('hydrates from prefs JSON', () async {
    final c = await _container(seed: {
      reminderSettingsStorageKey: '{"remindD7":true,"remindDaily":false}',
    });
    final s = c.read(reminderSettingsProvider);
    expect(s.remindD7, isTrue);
    expect(s.remindDaily, isFalse);
    expect(s.remindD1, isTrue, reason: 'default for missing');
  });

  test('set persists to prefs', () async {
    final c = await _container();
    final n = c.read(reminderSettingsProvider.notifier);
    await n.set(const ReminderSettings(remindD1: false));
    final raw = (await SharedPreferences.getInstance())
        .getString(reminderSettingsStorageKey);
    expect(raw, contains('"remindD1":false'));
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/providers/reminder_settings_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder_settings.dart';
import 'storage_service_provider.dart';

const reminderSettingsStorageKey = 'reminder_settings_v1';

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(reminderSettingsStorageKey);
    if (raw == null) return const ReminderSettings();
    try {
      return ReminderSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> set(ReminderSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(reminderSettingsStorageKey, jsonEncode(next.toJson()));
  }

  Future<void> update({
    bool? remindD1,
    bool? remindD3,
    bool? remindD7,
    bool? remindDaily,
  }) =>
      set(state.copyWith(
        remindD1: remindD1,
        remindD3: remindD3,
        remindD7: remindD7,
        remindDaily: remindDaily,
      ));
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/reminder_settings_provider.dart test/reminder_settings_provider_test.dart
git commit -m "feat(notifications): ReminderSettingsNotifier with prefs persistence"
```

---

### Task 2.3: Wire SettingsScreen toggles to provider

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Replace local state with provider reads**

In `lib/screens/settings_screen.dart`:

1. Delete the 4 `bool _remindD1` / `_remindD3` / `_remindD7` / `_remindDaily` field declarations from `_SettingsScreenState`.

2. In the `build` method, read the settings:

```dart
final reminder = ref.watch(reminderSettingsProvider);
final reminderN = ref.read(reminderSettingsProvider.notifier);
```

3. Replace each `_ToggleRow`'s `value:` and `onChanged:` with provider-driven equivalents. Example for D1:

```dart
_ToggleRow(
  label: '提前 1 天提醒',
  sub: '高优先级 · 推送 + 角标',
  value: reminder.remindD1,
  onChanged: (v) => reminderN.update(remindD1: v),
),
```

Do the same for D3, D7, Daily.

4. Add the provider import at top: `import '../providers/reminder_settings_provider.dart';`

- [ ] **Step 2: `flutter analyze` 0 errors + `flutter test` green**

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(settings): wire 临期提醒 toggles to ReminderSettings provider"
```

---

## Phase 3: Expiry scheduler

### Task 3.1: ExpiryScheduler — pure function

**Files:**
- Create: `lib/services/expiry_scheduler.dart`
- Create: `test/expiry_scheduler_test.dart`

The scheduler is a pure function — easy to test exhaustively.

- [ ] **Step 1: Tests**

```dart
// test/expiry_scheduler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/reminder_settings.dart';
import 'package:fresh_pantry/models/scheduled_notification.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/expiry_scheduler.dart';

Ingredient _ing({
  required String name,
  required DateTime expiry,
  DateTime? addedAt,
}) =>
    Ingredient(
      name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      category: FoodCategories.other, storage: IconType.fridge,
      expiryDate: expiry, addedAt: addedAt ?? DateTime(2026, 5, 1),
    );

void main() {
  group('ExpiryScheduler.compute', () {
    test('schedules per-item notification at 09:00 local D-1 before expiry',
        () {
      final now = DateTime(2026, 5, 15, 8, 0); // 8am
      final inventory = [
        _ing(name: '苹果', expiry: DateTime(2026, 5, 17)),
      ];
      final settings = const ReminderSettings(
        remindD1: true, remindD3: false, remindD7: false, remindDaily: false,
      );

      final result = ExpiryScheduler.compute(
        inventory: inventory,
        settings: settings,
        now: now,
      );

      // D-1 before 2026-05-17 = 2026-05-16 at 09:00
      expect(result, hasLength(1));
      expect(result.first.scheduledAt, DateTime(2026, 5, 16, 9, 0));
      expect(result.first.body, contains('苹果'));
      expect(result.first.kind, ScheduledNotificationKind.expiry);
    });

    test('skips per-item notifications whose D-N is already in the past', () {
      final now = DateTime(2026, 5, 15, 12, 0);
      final inventory = [
        _ing(name: '苹果', expiry: DateTime(2026, 5, 14)), // already expired
      ];
      final settings = const ReminderSettings(remindD1: true, remindDaily: false);

      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(result, isEmpty);
    });

    test('schedules D1 + D3 when both enabled', () {
      final now = DateTime(2026, 5, 15, 6, 0);
      final inventory = [_ing(name: '葱', expiry: DateTime(2026, 5, 20))];
      final settings = const ReminderSettings(
        remindD1: true, remindD3: true, remindD7: false, remindDaily: false,
      );

      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(result, hasLength(2));
      final scheduledAts = result.map((n) => n.scheduledAt).toSet();
      expect(scheduledAts, {
        DateTime(2026, 5, 19, 9, 0), // D-1
        DateTime(2026, 5, 17, 9, 0), // D-3
      });
    });

    test('daily summary scheduled once when remindDaily=true', () {
      final now = DateTime(2026, 5, 15, 8, 0);
      final inventory = <Ingredient>[];
      const settings = ReminderSettings(
        remindD1: false, remindD3: false, remindD7: false, remindDaily: true,
      );

      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      final daily = result
          .where((n) => n.kind == ScheduledNotificationKind.dailySummary)
          .toList();
      expect(daily, hasLength(1));
      expect(daily.first.scheduledAt.hour, 9);
    });

    test('no notifications when ingredient lacks expiryDate', () {
      final now = DateTime(2026, 5, 15);
      final inventory = [
        Ingredient(
          name: '盐', quantity: '1', unit: '袋', imageUrl: '',
          freshnessPercent: 1, state: FreshnessState.fresh,
          category: FoodCategories.other, storage: IconType.pantry,
          expiryDate: null,
        ),
      ];
      const settings = ReminderSettings(remindD1: true);
      final result = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      // Only the daily summary should remain (if enabled).
      expect(
        result.where((n) => n.kind == ScheduledNotificationKind.expiry),
        isEmpty,
      );
    });

    test('deterministic IDs across calls with same input', () {
      final now = DateTime(2026, 5, 15);
      final inventory = [_ing(name: '苹果', expiry: DateTime(2026, 5, 17))];
      const settings = ReminderSettings(remindD1: true, remindDaily: false);

      final r1 = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      final r2 = ExpiryScheduler.compute(
        inventory: inventory, settings: settings, now: now,
      );
      expect(r1.first.id, r2.first.id);
    });
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/services/expiry_scheduler.dart
import '../models/ingredient.dart';
import '../models/reminder_settings.dart';
import '../models/scheduled_notification.dart';

class ExpiryScheduler {
  ExpiryScheduler._();

  static const int dailySummaryHour = 9; // 09:00 local
  static const int dailySummaryId = 1; // reserved

  static List<ScheduledNotification> compute({
    required List<Ingredient> inventory,
    required ReminderSettings settings,
    required DateTime now,
  }) {
    final out = <ScheduledNotification>[];

    // Per-item D-N notifications
    for (final ing in inventory) {
      final expiry = ing.expiryDate;
      if (expiry == null) continue;
      for (final offset in settings.enabledOffsetDays) {
        final scheduledDate = DateTime(
          expiry.year, expiry.month, expiry.day - offset,
          dailySummaryHour, 0,
        );
        if (!scheduledDate.isAfter(now)) continue;
        out.add(ScheduledNotification(
          id: _idFor(ing, offset),
          title: '$offset 天后过期',
          body: '${ing.name} ${ing.quantity}${ing.unit} 还剩 $offset 天',
          scheduledAt: scheduledDate,
          kind: ScheduledNotificationKind.expiry,
        ));
      }
    }

    // Daily summary — single recurring slot
    if (settings.remindDaily) {
      final today9 = DateTime(now.year, now.month, now.day,
          dailySummaryHour, 0);
      final next = today9.isAfter(now)
          ? today9
          : today9.add(const Duration(days: 1));
      out.add(ScheduledNotification(
        id: dailySummaryId,
        title: '每日临期提醒',
        body: '查看今天到期 / 已过期食材',
        scheduledAt: next,
        kind: ScheduledNotificationKind.dailySummary,
      ));
    }

    return out;
  }

  /// Deterministic id from name + storage + addedAt + offset.
  /// Restricted to int32 range so flutter_local_notifications accepts it.
  static int _idFor(Ingredient ing, int offset) {
    final base =
        '${ing.name}|${ing.storage.name}|${ing.addedAt?.millisecondsSinceEpoch ?? 0}|$offset';
    var hash = 0;
    for (final code in base.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == dailySummaryId) hash++; // avoid collision with reserved id
    return hash;
  }
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/expiry_scheduler.dart test/expiry_scheduler_test.dart
git commit -m "feat(notifications): ExpiryScheduler pure-function compute"
```

---

### Task 3.2: notificationSyncProvider — listen + diff + dispatch

**Files:**
- Create: `lib/providers/notification_sync_provider.dart`

This provider listens to `inventoryProvider` and `reminderSettingsProvider`. On change, it recomputes the expected notification set and calls `NotificationService.syncAll(...)`. It tracks `_previousIds` internally so cancellations happen cleanly.

- [ ] **Step 1: Implement**

```dart
// lib/providers/notification_sync_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../models/reminder_settings.dart';
import '../services/expiry_scheduler.dart';
import 'inventory_provider.dart';
import 'notification_service_provider.dart';
import 'reminder_settings_provider.dart';

class NotificationSyncNotifier extends Notifier<List<int>> {
  @override
  List<int> build() {
    // Subscribe to both providers so changes trigger rebuilds.
    final inventory = ref.watch(inventoryProvider);
    final settings = ref.watch(reminderSettingsProvider);

    // Schedule asynchronously after build so we don't perform IO during widget tree build.
    Future.microtask(() => _resync(inventory, settings));

    // The state we return is the IDs we last scheduled (for cancellation on next sync).
    return state;
  }

  Future<void> _resync(
    List<Ingredient> inventory,
    ReminderSettings settings,
  ) async {
    final service = ref.read(notificationServiceProvider);
    if (!service.permissionGranted) return;
    final next = ExpiryScheduler.compute(
      inventory: inventory,
      settings: settings,
      now: DateTime.now(),
    );
    final nextIds = next.map((n) => n.id).toList();
    await service.syncAll(next, previousIds: state);
    state = nextIds;
  }
}

final notificationSyncProvider =
    NotifierProvider<NotificationSyncNotifier, List<int>>(
        NotificationSyncNotifier.new);
```

> NOTE: This provider exists for its **side effect**. To trigger it, something must `read` or `watch` it. We do that in Task 4 (settings screen) and in main.dart (Phase 6).

- [ ] **Step 2: Commit**

```bash
git add lib/providers/notification_sync_provider.dart
git commit -m "feat(notifications): notificationSyncProvider listens + dispatches schedule diffs"
```

---

## Phase 4: Permission UX

### Task 4.1: Lazy permission request on first toggle

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Wrap toggle onChanged with permission gate**

In `_SettingsScreenState`, wrap the toggle `onChanged` callbacks:

```dart
Future<void> _onToggleChanged(bool newValue, Future<void> Function() apply) async {
  if (newValue) {
    final service = ref.read(notificationServiceProvider);
    if (!service.permissionGranted) {
      final granted = await service.requestPermission();
      if (!granted) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('未开启通知权限'),
            content: const Text('系统通知权限未开启,无法发送临期提醒。请在 系统设置 → 通知 中允许。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('好'),
              ),
            ],
          ),
        );
        return; // Don't toggle on if permission denied.
      }
    }
  }
  await apply();
}
```

Then in each `_ToggleRow`, wrap the onChanged:

```dart
_ToggleRow(
  label: '提前 1 天提醒',
  ...
  value: reminder.remindD1,
  onChanged: (v) => _onToggleChanged(v, () => reminderN.update(remindD1: v)),
),
```

Repeat for D3, D7, Daily.

Add import: `import '../providers/notification_service_provider.dart';`

- [ ] **Step 2: `flutter analyze` 0 errors**

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(notifications): lazy permission request on first toggle ON"
```

---

### Task 4.2: Settings banner when permission denied

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Add banner widget above 临期提醒 section**

In `_SettingsScreenState.build`, before the 临期提醒 `FkSectionHead`, check the service state and show a banner if any toggle is ON but permission is denied:

```dart
final anyReminderOn = reminder.remindD1 || reminder.remindD3 ||
    reminder.remindD7 || reminder.remindDaily;
final service = ref.read(notificationServiceProvider);
final permissionMissing = anyReminderOn && !service.permissionGranted;

if (permissionMissing)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fkWarnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.warning_amber, color: AppColors.fkWarn),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '系统通知权限未开启,提醒不会送达。请去 系统设置 → 通知 中允许。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  ),
const SizedBox(height: 12),
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(settings): warn when reminder toggles enabled but OS permission denied"
```

---

## Phase 5: 今晚做啥 — boost recipes that use expiring items

### Task 5.1: Enhance `recommendedRecipesProvider` scoring

**Files:**
- Modify: `lib/providers/recipe_provider.dart`
- Modify: `test/recommended_recipes_test.dart` (or create if doesn't exist)

- [ ] **Step 1: Locate current scoring (around line 174-220 in `lib/providers/recipe_provider.dart`)**

The current provider scores by `matched / total ingredients`. We want to boost the score when matched ingredients include items whose `state == FreshnessState.expiringSoon` or `expired`.

- [ ] **Step 2: Add tests**

```dart
// test/recommended_recipes_test.dart (modify if exists, create if not)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ingredient _ing({
  required String name,
  FreshnessState state = FreshnessState.fresh,
}) =>
    Ingredient(
      name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: state == FreshnessState.fresh ? 1.0 : 0.2,
      state: state,
      category: FoodCategories.other,
      storage: IconType.fridge,
    );

Recipe _recipe(String id, String name, List<String> ingredientNames) =>
    Recipe(
      id: id, name: name, category: '中餐',
      difficulty: 1, cookingMinutes: 10, description: '',
      ingredients: ingredientNames
          .map((n) => RecipeIngredient(name: n, quantity: '1', unit: '个'))
          .toList(),
      steps: const [],
    );

Future<ProviderContainer> _container({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(inventory),
    recipesProvider.overrideWith((ref) => Future.value(recipes)),
  ]);
}

void main() {
  test(
      'recipe using an expiringSoon ingredient ranks above an equal-match fresh one',
      () async {
    final inventory = [
      _ing(name: '番茄', state: FreshnessState.expiringSoon),
      _ing(name: '鸡蛋', state: FreshnessState.fresh),
      _ing(name: '黄瓜', state: FreshnessState.fresh),
    ];
    final recipes = [
      _recipe('a', '番茄炒蛋', ['番茄', '鸡蛋']),    // uses expiring
      _recipe('b', '黄瓜炒蛋', ['黄瓜', '鸡蛋']),    // doesn't
    ];
    final c = await _container(inventory: inventory, recipes: recipes);
    // Wait for the async recipesProvider to resolve.
    await c.read(recipesProvider.future);
    final ranked = c.read(recommendedRecipesProvider);
    expect(ranked.first.id, 'a',
        reason: 'expiringSoon-boost should put 番茄炒蛋 first');
  });
}
```

- [ ] **Step 3: Run** — FAIL (or wrong order).

- [ ] **Step 4: Implement boost**

Locate the scoring block (around line 200 in `lib/providers/recipe_provider.dart`). Modify the scoring to consume an `expiringNameSet` and add a boost. The exact lines may vary — read the file first.

Pseudo-patch:

```dart
final inventoryItems = ref.read(inventoryProvider);
final expiringNames = inventoryItems
    .where((i) => i.state == FreshnessState.expiringSoon || i.state == FreshnessState.expired)
    .map((i) => _norm(i.name))
    .toSet();

// In the scored.map:
final scored = recipes.map((recipe) {
  final matched = _matchedIngredientCountForNames(inventoryNames, recipe);
  if (matched == 0 || recipe.ingredients.isEmpty) {
    return (recipe: recipe, score: 0.0);
  }
  final base = matched / recipe.ingredients.length;
  final usesExpiring = recipe.ingredients.any((ri) => expiringNames.contains(_norm(ri.name)));
  final boost = usesExpiring ? 0.5 : 0.0;
  return (recipe: recipe, score: base + boost);
});
```

> `_norm` is the existing private helper in the file.

- [ ] **Step 5: Run** — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/recipe_provider.dart test/recommended_recipes_test.dart
git commit -m "feat(recipes): boost recipes that use expiring inventory"
```

---

## Phase 6: Bootstrap permission check + tap handler

### Task 6.1: Read service permission state from system after bootstrap

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: After `notificationService.init()`, query current state**

This is important because the user may have granted permission previously; the plugin doesn't auto-rehydrate `permissionGranted`. Use the same query path as `requestPermission` but without asking:

```dart
// In main(), after `await notificationService.init();`:
// (No way to query without re-asking on iOS. So we set permissionGranted based on
//  the success of a no-op call, OR simply leave it false and let the first toggle
//  request it again — that's fine, iOS will return the cached answer.)
```

> DECISION: Leave it as-is. The first toggle will trigger `requestPermission`, which on iOS returns the cached answer without showing a prompt. No user-visible behavior change. Skip this task.

- [ ] **Step 2: No-op — close task without commit, document the decision in this plan.**

Mark the plan's task #6.1 as "intentionally skipped" — no code changes needed.

---

### Task 6.2: Watch notificationSyncProvider at app shell

**Files:**
- Modify: `lib/app.dart` (or wherever the top-level Riverpod tree lives — read the file first)

- [ ] **Step 1: Make AppShell read notificationSyncProvider so it actually fires**

In the top-level `ConsumerWidget` (e.g., `AppShell` or `FreshPantryApp`):

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.watch(notificationSyncProvider); // side-effect: schedules on inventory/settings change
  // ... existing build code
}
```

Add import: `import 'providers/notification_sync_provider.dart';`

- [ ] **Step 2: Run `flutter test` — verify no regressions in widget tests**

(Some tests may break if they don't override `notificationServiceProvider`. If that happens, add a no-op fake `NotificationService` test override; see Task 6.3.)

- [ ] **Step 3: Commit**

```bash
git add lib/app.dart
git commit -m "feat(notifications): watch notificationSyncProvider at app shell"
```

---

### Task 6.3: Fix any broken widget tests by overriding notificationServiceProvider

**Files:**
- Modify: affected `test/*.dart` files

Each ProviderScope test override list must now include `notificationServiceProvider`. Use a fake:

```dart
class _FakeNotificationService implements NotificationService {
  @override bool get isInitialized => true;
  @override bool get permissionGranted => false; // safe default — no actual scheduling
  @override Future<void> init({void Function(int)? onTap}) async {}
  @override Future<bool> requestPermission() async => false;
  @override Future<void> schedule(ScheduledNotification n) async {}
  @override Future<void> syncAll(List<ScheduledNotification> next, {required List<int> previousIds}) async {}
  @override Future<void> cancel(int id) async {}
  @override void debugSetState({required bool initialized, required bool permission}) {}
}
```

Place in a new shared test helper: `test/helpers/fake_notification_service.dart`.

- [ ] **Step 1: Create helper file**
- [ ] **Step 2: Update affected tests to override the provider**
- [ ] **Step 3: Run `flutter test` — full suite green**
- [ ] **Step 4: Commit**

```bash
git add test/helpers/fake_notification_service.dart test/<each affected>.dart
git commit -m "test(notifications): override notificationServiceProvider with fake in widget tests"
```

---

## Phase 7: Integration verification

### Task 7.1: `flutter test` + `flutter analyze`

- [ ] Run `flutter test` — full suite green.
- [ ] Run `flutter analyze` — 0 errors. Pre-existing infos OK.

### Task 7.2: Manual smoke checklist

```bash
flutter run -d ios
```

- Settings → 临期提醒 → toggle "提前 1 天提醒" ON → iOS shows permission prompt → allow → toggle visually persists → reopen App → still ON.
- Reject permission once → toggle reverts → banner appears in 临期提醒 section.
- With permission ON, add an ingredient with expiry 3 days from now → no immediate notification; in Settings under Apps → fresh_pantry, the OS shows 1 pending notification.
- Wait a day (or change device time forward) → notification fires at 09:00 next day with "X 还剩 1 天".
- Delete ingredient → no notification fires.
- Dashboard's "今日推荐" — if any expiring inventory exists, the top recipe should now favour using it.

### Task 7.3: Commit any final cleanup + push (push deferred to user request)

---

## Self-Review

**Spec coverage:**
- ✅ `flutter_local_notifications` integrated (Task 1.1, 1.2, 1.4)
- ✅ ReminderSettings persisted (Task 2.1, 2.2, 2.3)
- ✅ ExpiryScheduler pure function with 6 tests covering edge cases (Task 3.1)
- ✅ notificationSyncProvider listens + dispatches (Task 3.2, 6.2)
- ✅ Lazy permission request + denial banner (Task 4.1, 4.2)
- ✅ 今晚做啥 = recipe boost for expiring items (Task 5.1)
- ✅ Existing widget tests stay green via fake service (Task 6.3)

**Placeholder scan:**
- Task 6.1 explicitly marked skipped (decision documented inline) — not a placeholder, a deliberate no-op.
- All other tasks have full runnable Dart code.

**Type consistency:**
- `ScheduledNotification` / `ScheduledNotificationKind` defined in Task 1.3, used in Tasks 1.2, 3.1, 3.2, 6.3.
- `ReminderSettings` defined in 2.1, used in 2.2, 2.3, 3.1, 3.2, 4.1, 4.2.
- `NotificationService` API surface (`init`, `requestPermission`, `schedule`, `syncAll`, `cancel`, `isInitialized`, `permissionGranted`) defined in 1.2, used in 3.2, 4.1, 4.2, 6.3.

**Risk register:**
- **iOS background scheduling reliability**: `zonedSchedule` should fire reliably with `exactAllowWhileIdle` on Android and absolute time on iOS. If users report missed deliveries, investigate — but not in scope here.
- **Daily summary firing when nothing's expiring**: the spec says "skip when 0 items today". Current implementation always schedules the daily slot; the BODY of the summary is generic. If the user finds the empty summary annoying, a Stage 2.5 enhancement could include count in the body or skip when zero — defer.
- **Existing widget tests using ProviderScope**: 30+ tests may break when notificationSyncProvider tries to read notificationServiceProvider. Task 6.3 mitigates via a shared fake, but the migration sweep may surface unexpected test failures requiring per-test fixes. If sweep is large, consider making `notificationSyncProvider` opt-in via an override flag.
- **Notification ID collisions**: int hash is `0x7fffffff` masked; collisions theoretically possible across 10k+ ingredients, but at self-use scale (<200 ingredients) probability is negligible.

---

## Out of plan — Stage 2.5 backlog

- Per-user notification time picker (currently 9am hardcoded).
- Snooze / "已查看" actions on the notification itself.
- Low-stock notifications (separate flow).
- Notification reliability monitoring.
- Daily summary body that includes actual count of items.
