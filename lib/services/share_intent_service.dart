import 'dart:async';

import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

typedef ClipboardReader = Future<String?> Function();
typedef Clock = DateTime Function();

Future<String?> _defaultClipboardRead() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text;
}

class ClipboardUrlDetector {
  ClipboardUrlDetector({
    this.ignoreCooldown = const Duration(minutes: 30),
    ClipboardReader? clipboardReader,
    Clock? clock,
  })  : _read = clipboardReader ?? _defaultClipboardRead,
        _clock = clock ?? DateTime.now;

  final Duration ignoreCooldown;
  final ClipboardReader _read;
  final Clock _clock;

  String? _ignoredUrl;
  DateTime? _ignoredAt;

  /// Returns the first http(s) URL in the clipboard, or null when missing /
  /// suppressed by the cooldown window.
  Future<String?> peek() async {
    final text = await _read();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'https?://[^\s)\]"]+').firstMatch(text);
    final url = match?.group(0);
    if (url == null) return null;
    if (_ignoredUrl == url && _ignoredAt != null) {
      final elapsed = _clock().difference(_ignoredAt!);
      if (elapsed < ignoreCooldown) return null;
    }
    return url;
  }

  void markIgnored(String url) {
    _ignoredUrl = url;
    _ignoredAt = _clock();
  }
}

abstract class SystemShareSource {
  Stream<String> get incomingTextStream;
  Future<String?> consumeInitialText();
}

/// In-memory source for tests.
class InMemoryShareSource implements SystemShareSource {
  final _ctrl = StreamController<String>.broadcast();
  String? _initial;

  void emit(String text) => _ctrl.add(text);
  set initial(String? v) => _initial = v;

  @override
  Stream<String> get incomingTextStream => _ctrl.stream;

  @override
  Future<String?> consumeInitialText() async {
    final t = _initial;
    _initial = null;
    return t;
  }

  void close() => _ctrl.close();
}

/// Extracts the first http(s) URL from arbitrary text.
String? extractUrl(String text) {
  final m = RegExp(r'https?://[^\s)\]"]+').firstMatch(text);
  return m?.group(0);
}

class ReceiveSharingIntentSource implements SystemShareSource {
  @override
  Stream<String> get incomingTextStream =>
      ReceiveSharingIntent.instance.getMediaStream().map((items) =>
          items.map((e) => e.path).join(' '));

  @override
  Future<String?> consumeInitialText() async {
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    final text = initial.map((e) => e.path).join(' ');
    ReceiveSharingIntent.instance.reset();
    return text.isEmpty ? null : text;
  }
}
