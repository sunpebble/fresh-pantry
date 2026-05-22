/// Low-level key-value storage adapter.
///
/// Defines a seam between domain repos and the underlying persistence
/// mechanism. Two adapters exist from day one:
/// - [SharedPrefsStorageAdapter] — production, backed by SharedPreferences
/// - [InMemoryStorageAdapter] — tests, backed by a Map
abstract class StorageAdapter {
  /// Returns the stored value for [key], or `null` if not present.
  String? read(String key);

  /// Persists [value] under [key].
  ///
  /// Implementations should be fire-and-forget where possible; callers
  /// do not block on the returned future.
  Future<void> write(String key, String value);
}
