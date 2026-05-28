import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/invite_link_service.dart';

final inviteLinkSourceProvider = Provider<InviteLinkSource>((_) {
  return const NoOpInviteLinkSource();
});
