import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers/ai_settings_provider.dart' show aiSettingsStorageKey;
import '../providers/custom_recipe_provider.dart' show customRecipesStorageKey;
import '../providers/inventory_provider.dart'
    show addHistoryStorageKey, inventoryItemsStorageKey;
import '../providers/shopping_provider.dart' show shoppingItemsStorageKey;

class BackupVersionException implements Exception {
  const BackupVersionException(this.message);
  final String message;
  @override
  String toString() => 'BackupVersionException: $message';
}

class BackupService {
  BackupService._();

  static const int backupVersion = 1;

  /// User-data SharedPreferences keys that are included in backups.
  /// Cache keys (e.g. `food_details_cache`) are intentionally excluded —
  /// they regenerate and would bloat the blob.
  static const List<String> userDataKeys = [
    inventoryItemsStorageKey,
    addHistoryStorageKey,
    shoppingItemsStorageKey,
    customRecipesStorageKey,
    aiSettingsStorageKey,
  ];

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

  /// Keys whose payload must decode to a JSON list (matches what the
  /// inventory/shopping/custom-recipe repos expect on load).
  static const Set<String> _listPayloadKeys = {
    inventoryItemsStorageKey,
    shoppingItemsStorageKey,
    customRecipesStorageKey,
  };

  /// Keys whose payload must decode to a JSON object (add-history map and the
  /// AI-settings map).
  static const Set<String> _mapPayloadKeys = {
    addHistoryStorageKey,
    aiSettingsStorageKey,
  };

  /// Imports a decoded backup [envelope] into [prefs] atomically.
  ///
  /// Every known payload is parse-validated BEFORE any key is written; if any
  /// payload is present but structurally invalid (e.g. a truncated
  /// `inventory_items` blob that no longer decodes to a list) this throws a
  /// [FormatException] and writes NOTHING, so a version-valid backup with a
  /// corrupted inner payload can never silently wipe the existing data.
  ///
  /// [onImported] is awaited only after a successful, complete write. The
  /// caller uses it to make the import authoritative against IN-MEMORY state
  /// (e.g. reload the affected Riverpod notifiers from the freshly written
  /// prefs) before stale notifier/sync state can persist old data back over
  /// the import. It is never invoked when the import throws.
  static Future<void> importFromMap(
    SharedPreferences prefs,
    Map<String, dynamic> envelope, {
    Future<void> Function()? onImported,
  }) async {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Backup data is not a JSON object');
    }

    // Phase 1 — validate everything; collect the writes but apply none yet.
    final writes = <String, String>{};
    for (final key in userDataKeys) {
      final value = data[key];
      if (value == null) continue;
      if (value is! String) {
        throw FormatException('Backup payload for "$key" is not a string');
      }
      _validatePayload(key, value);
      writes[key] = value;
    }

    // Phase 2 — all payloads valid; persist them.
    for (final entry in writes.entries) {
      await prefs.setString(entry.key, entry.value);
    }

    if (onImported != null) await onImported();
  }

  static void _validatePayload(String key, String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw FormatException('Backup payload for "$key" is not valid JSON');
    }
    if (_listPayloadKeys.contains(key) && decoded is! List) {
      throw FormatException('Backup payload for "$key" must be a JSON list');
    }
    if (_mapPayloadKeys.contains(key) && decoded is! Map) {
      throw FormatException('Backup payload for "$key" must be a JSON object');
    }
  }

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
