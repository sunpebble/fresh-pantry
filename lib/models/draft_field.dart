import 'package:flutter/foundation.dart';

enum DraftSource { ai, user, hybrid }

@immutable
class DraftField<T> {
  const DraftField({required this.value, required this.source});

  final T value;
  final DraftSource source;

  factory DraftField.ai(T value) => DraftField(value: value, source: DraftSource.ai);
  factory DraftField.user(T value) => DraftField(value: value, source: DraftSource.user);

  DraftField<T> editedTo(T next) =>
      DraftField(value: next, source: DraftSource.user);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftField<T> && other.value == value && other.source == source);

  @override
  int get hashCode => Object.hash(value, source);
}
