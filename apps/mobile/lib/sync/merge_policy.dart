class MergeResult {
  MergeResult({
    required Map<String, dynamic> value,
    required this.conflict,
    List<String> conflictFields = const [],
  }) : value = _deepFreezeObject(value),
       conflictFields = List.unmodifiable(conflictFields);

  final Map<String, dynamic> value;
  final bool conflict;
  final List<String> conflictFields;
}

MergeResult mergeRemotePatch({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required Map<String, dynamic> patch,
  required int? baseVersion,
  required int remoteVersion,
}) {
  if (baseVersion == null || baseVersion == remoteVersion) {
    return MergeResult(value: {...remote, ...patch}, conflict: false);
  }

  final merged = Map<String, dynamic>.from(remote);
  final conflicts = <String>[];

  for (final entry in patch.entries) {
    final field = entry.key;
    final localValue = local[field];
    final remoteValue = remote[field];
    final patchValue = entry.value;

    if (_jsonValueEquals(remoteValue, localValue) ||
        _jsonValueEquals(remoteValue, patchValue)) {
      merged[field] = patchValue;
      continue;
    }

    merged[field] = patchValue;
    conflicts.add(field);
  }

  return MergeResult(
    value: merged,
    conflict: conflicts.isNotEmpty,
    conflictFields: conflicts,
  );
}

bool _jsonValueEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) return false;
      if (!_jsonValueEquals(entry.value, right[entry.key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (!_jsonValueEquals(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

Map<String, dynamic> _deepFreezeObject(Map<String, dynamic> value) {
  return Map.unmodifiable(
    value.map((key, nested) => MapEntry(key, _deepFreezeValue(nested))),
  );
}

Object? _deepFreezeValue(Object? value) {
  if (value is Map) {
    return _deepFreezeObject(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return List.unmodifiable(value.map(_deepFreezeValue));
  }
  return value;
}
