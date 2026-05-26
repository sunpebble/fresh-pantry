import 'package:flutter_riverpod/flutter_riverpod.dart';

mixin ReviewNotifierBase<TState> on Notifier<TState> {
  void clear();

  Future<void> applyAndClear(Future<void> Function() apply) async {
    await apply();
    clear();
  }
}
