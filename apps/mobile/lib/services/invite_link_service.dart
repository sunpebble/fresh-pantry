import 'dart:async';

import 'package:app_links/app_links.dart';

abstract class InviteLinkSource {
  Stream<String> get incomingLinks;
  Future<String?> consumeInitialLink();
}

class AppLinksInviteLinkSource implements InviteLinkSource {
  AppLinksInviteLinkSource({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Stream<String> get incomingLinks =>
      _appLinks.uriLinkStream.map((uri) => uri.toString());

  @override
  Future<String?> consumeInitialLink() async {
    return (await _appLinks.getInitialLink())?.toString();
  }
}

class InMemoryInviteLinkSource implements InviteLinkSource {
  final _controller = StreamController<String>.broadcast();
  String? _initial;

  set initial(String? value) => _initial = value;

  void emit(String link) => _controller.add(link);

  @override
  Stream<String> get incomingLinks => _controller.stream;

  @override
  Future<String?> consumeInitialLink() async {
    final link = _initial;
    _initial = null;
    return link;
  }

  Future<void> close() => _controller.close();
}

class NoOpInviteLinkSource implements InviteLinkSource {
  const NoOpInviteLinkSource();

  @override
  Stream<String> get incomingLinks => const Stream.empty();

  @override
  Future<String?> consumeInitialLink() async => null;
}

InviteLinkSource createInviteLinkSource() {
  return AppLinksInviteLinkSource();
}
