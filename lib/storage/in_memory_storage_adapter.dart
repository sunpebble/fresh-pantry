import 'storage_adapter.dart';

class InMemoryStorageAdapter implements StorageAdapter {
  final Map<String, String> _store = {};

  @override
  String? read(String key) => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }
}
