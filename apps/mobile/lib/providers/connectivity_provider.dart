import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` when at least one network transport is available. Overridable
/// in tests with a controlled stream.
final connectivityOnlineProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
});
