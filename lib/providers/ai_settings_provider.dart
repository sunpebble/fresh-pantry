import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_settings.dart';
import '../storage/ai_settings_repo.dart';
import 'storage_service_provider.dart';

class AiSettingsNotifier extends Notifier<AiSettings> {
  late AiSettingsRepo _repo;

  @override
  AiSettings build() {
    _repo = ref.read(aiSettingsRepoProvider);
    return _repo.load();
  }

  Future<void> save(AiSettings next) async {
    _repo.save(next);
    state = next;
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
