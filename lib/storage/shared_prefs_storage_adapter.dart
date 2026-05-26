import 'package:shared_preferences/shared_preferences.dart';
import 'storage_adapter.dart';

class SharedPrefsStorageAdapter implements StorageAdapter {
  final SharedPreferences _prefs;

  SharedPrefsStorageAdapter(this._prefs);

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }
}
