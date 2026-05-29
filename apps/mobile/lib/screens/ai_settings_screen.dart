import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_settings.dart';
import '../providers/ai_settings_provider.dart';
import '../services/ai_client.dart';
import '../theme/app_theme.dart';
import '../utils/ai_base_url.dart';

class ConnectionTestResult {
  const ConnectionTestResult.ok() : success = true, message = '连接成功';
  const ConnectionTestResult.error(this.message) : success = false;
  final bool success;
  final String message;
}

typedef ConnectionTestFn = Future<ConnectionTestResult> Function(AiSettings settings);

Future<ConnectionTestResult> defaultTestConnection(AiSettings settings) async {
  try {
    final probeSettings = settings.copyWith(
      baseUrl: normalizeAiBaseUrl(settings.baseUrl),
      timeout: settings.timeout < const Duration(seconds: 15)
          ? const Duration(seconds: 15)
          : settings.timeout,
    );
    await AiClient.chat(
      settings: probeSettings,
      messages: [AiMessage.text('user', 'reply with: ok')],
    );
    return const ConnectionTestResult.ok();
  } on AiException catch (e) {
    return ConnectionTestResult.error(e.message);
  } catch (e) {
    return ConnectionTestResult.error('未知错误: $e');
  }
}

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key, this.testConnection});

  final ConnectionTestFn? testConnection;

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _timeout;

  bool _testing = false;
  bool _saving = false;
  ConnectionTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final s = ref.read(aiSettingsProvider);
    _baseUrl = TextEditingController(text: s.baseUrl);
    _apiKey = TextEditingController(text: s.apiKey);
    _model = TextEditingController(text: s.model);
    _timeout = TextEditingController(text: s.timeout.inSeconds.toString());
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _timeout.dispose();
    super.dispose();
  }

  AiSettings _currentInputs() {
    return AiSettings(
      baseUrl: normalizeAiBaseUrl(_baseUrl.text),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      timeout: Duration(seconds: int.tryParse(_timeout.text.trim()) ?? 60),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final next = _currentInputs();
    try {
      await ref.read(aiSettingsProvider.notifier).save(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final fn = widget.testConnection ?? defaultTestConnection;
    final result = await fn(_currentInputs());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            key: const Key('ai_base_url'),
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://cpa.kunish.eu.org/v1',
              helperText: '填写到 /v1 即可；仅填域名也会自动补全',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('ai_api_key'),
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('ai_model'),
            controller: _model,
            decoration: const InputDecoration(labelText: 'Model', hintText: 'gpt-4o'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('ai_timeout'),
            controller: _timeout,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Timeout (秒)'),
          ),
          const SizedBox(height: AppSpacing.xxl),
          OutlinedButton(
            key: const Key('ai_test_connection'),
            onPressed: _testing ? null : _runTest,
            child: _testing
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('测试连接'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _testResult!.message,
              style: TextStyle(
                color: _testResult!.success
                    ? AppColors.primary
                    : AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('ai_save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            '明文存于本机 SharedPreferences。',
            style: TextStyle(fontSize: AppFontSize.xs, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
