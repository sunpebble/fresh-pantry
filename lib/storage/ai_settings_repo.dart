import 'dart:convert';
import '../models/ai_settings.dart';
import 'storage_adapter.dart';

class AiSettingsRepo {
  static const _storageKey = 'ai_settings_v1';

  final StorageAdapter _adapter;

  AiSettingsRepo(this._adapter);

  AiSettings load() {
    final raw = _adapter.read(_storageKey);
    if (raw == null || raw.isEmpty) return AiSettings.empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiSettings.fromJson(map);
    } catch (_) {
      return AiSettings.empty;
    }
  }

  void save(AiSettings settings) {
    _adapter.write(_storageKey, jsonEncode(settings.toJson()));
  }
}
